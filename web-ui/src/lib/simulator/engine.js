import { runYosys } from '@yowasp/yosys';
import { VerilogXMLParser } from '../../../vendor/8bitworkshop/hdl/vxmlparser';
import { primitiveDeclarations, primitiveModels, pixelPreviewModel } from './primitives.js';
import { Framebuffer, GC9A01 } from './display.js';
import { loadMemory } from './memory.js';
import { TraceCapture, signalCatalog } from './trace.js';
import { PackedRuntime } from './packedRuntime.js';

const encoder = new TextEncoder(), decoder = new TextDecoder();
const asText = value => typeof value === 'string' ? value : decoder.decode(value);
const knownPorts = new Set(['clk_ext', 'btn', 'led', 'pmod_j1', 'pmod_j2', 'interconnect', 's', 'oled_scl', 'oled_sda', 'oled_dc', 'oled_cs', 'oled_rst']);
const primitiveNames = new Set(['OSCG', 'EHXPLLL', 'ODDRX1F']);
const pinNames = ['oled_scl', 'oled_sda', 'oled_dc', 'oled_cs', 'oled_rst'];

function parameter(value, fallback) {
  if (value === undefined) return fallback;
  if (typeof value === 'number') return value;
  if (/^[01]+$/.test(value)) {
    const padded = value.padStart(Math.ceil(value.length / 8) * 8, '0');
    const chars = padded.match(/.{8}/g).map(byte => String.fromCharCode(parseInt(byte, 2))).join('');
    return /^\d+$/.test(chars) ? Number(chars) : parseInt(value, 2);
  }
  return Number(value);
}
function textParameter(value, fallback) {
  if (value === undefined) return fallback;
  if (/^[01]+$/.test(value)) return value.padStart(Math.ceil(value.length/8)*8,'0').match(/.{8}/g).map(byte=>String.fromCharCode(parseInt(byte,2))).join('').replace(/^\0+/, '');
  return value;
}

export async function prepareSimulation(files, mode = 'pixel', externalHz = 10_000_000) {
  if (!['pixel', 'spi'].includes(mode)) throw new Error('Unknown OLED rendering mode.');
  if (!Number.isFinite(externalHz) || externalHz < 1 || externalHz > 200_000_000) throw new Error('External clock must be between 1 Hz and 200 MHz.');
  const sourceNames = Object.keys(files).filter(name => name.endsWith('.v'));
  if (!sourceNames.length) throw new Error('Add a Verilog top module first.');
  if (Object.keys(files).some(name => name.startsWith('__gm_'))) throw new Error('Filenames beginning __gm_ are reserved for simulation.');
  const fs = Object.fromEntries(Object.entries(files).map(([name, content]) => [name, encoder.encode(content)]));
  fs['__gm_cells.v'] = encoder.encode(primitiveDeclarations);
  let netlist;
  try {
    const output = await runYosys(['-Q', '-l', '__gm_yosys.log', '__gm_cells.v', ...sourceNames, '-p', 'hierarchy -check -top top; proc; write_json __gm_metadata.json'], fs);
    netlist = JSON.parse(asText(output['__gm_metadata.json']));
  } catch (error) {
    const log = error.files?.['__gm_yosys.log'];
    throw new Error(`Simulation elaboration failed:\n${log ? asText(log).slice(-6000) : error.message}`);
  }
  const ports = netlist.modules.top?.ports;
  if (!ports) throw new Error('The project must define module top.');
  for (const [name, port] of Object.entries(ports)) {
    if (!knownPorts.has(name) && port.direction !== 'output') throw new Error(`Unsupported board input ${name}. Use the GreyMecha top-level port names.`);
  }
  const btnWidth = ports.btn?.bits.length ?? 0;
  if (ports.btn && (ports.btn.direction !== 'input' || ![5, 7].includes(btnWidth) || ports.btn.offset)) throw new Error('btn must be an input [4:0] or [6:0].');
  if (ports.led && (ports.led.direction !== 'output' || ports.led.bits.length !== 8 || ports.led.offset)) throw new Error('led must be output [7:0].');
  if (ports.clk_ext && (ports.clk_ext.direction !== 'input' || ports.clk_ext.bits.length !== 1)) throw new Error('clk_ext must be a scalar input.');
  const instances = [];
  function visit(type, path, mapping = {}) {
    const mod = netlist.modules[type];
    const ref = bit => typeof bit === 'string' ? bit : (mapping[bit] ?? `${path}:${bit}`);
    for (const [name, cell] of Object.entries(mod.cells ?? {})) {
      const child = netlist.modules[cell.type];
      if (!child) continue;
      const baseType = child.attributes?.hdlname?.split(' ')[0] ?? [...primitiveNames, 'oled_gc9a01'].find(name => cell.type === name || cell.type.includes(`\\${name}\\`) || cell.type.endsWith(`\\${name}`)) ?? cell.type;
      if (parameter(child.attributes?.blackbox, 0) && !primitiveNames.has(baseType)) throw new Error(`Unsupported simulation primitive ${baseType}.`);
      const pins = Object.fromEntries(Object.entries(cell.connections).map(([key, bits]) => [key, bits.map(ref)]));
      const item = { type: baseType, path: `${path}.${name}`, pins, params: { ...child.parameter_default_values, ...cell.parameters } };
      if (primitiveNames.has(baseType) || baseType === 'oled_gc9a01') instances.push(item);
      if (!primitiveNames.has(baseType)) {
        const aliases = {};
        for (const [key, port] of Object.entries(child.ports ?? {})) port.bits.forEach((bit, index) => { aliases[bit] = pins[key]?.[index] ?? `${item.path}:${bit}`; });
        visit(cell.type, item.path, aliases);
      }
    }
  }
  visit('top', 'dut');
  const oscillators = instances.filter(item => item.type === 'OSCG');
  const plls = instances.filter(item => item.type === 'EHXPLLL');
  if (oscillators.length > 1 || plls.length > 1) throw new Error('This simulator supports one OSCG and one PLL per design.');
  const oscDiv = parameter(oscillators[0]?.params.DIV, 6);
  if (!Number.isInteger(oscDiv) || oscDiv < 2 || oscDiv > 128) throw new Error(`Unsupported OSCG divider ${oscDiv}.`);
  const oscHz = 310_000_000 / oscDiv;
  let pllHz = 0;
  if (plls.length) {
    const pll = plls[0];
    if (!oscillators.length || pll.pins.CLKI?.[0] !== oscillators[0].pins.OSC?.[0]) throw new Error('The supported PLL must be driven directly by OSCG.');
    if (pll.pins.RST?.[0] !== '0' || pll.pins.STDBY?.[0] !== '0' || pll.pins.ENCLKOP?.[0] !== '0') throw new Error('Dynamic PLL reset, standby, and enable are not supported.');
    for (const [key, expected] of Object.entries({ FEEDBK_PATH:'CLKOP',CLKOP_ENABLE:'ENABLED',PLLRST_ENA:'DISABLED',DPHASE_SOURCE:'DISABLED',STDBY_ENABLE:'DISABLED',INTFB_WAKE:'DISABLED',OUTDIVIDER_MUXA:'DIVA',OUTDIVIDER_MUXB:'DIVB',OUTDIVIDER_MUXC:'DIVC',OUTDIVIDER_MUXD:'DIVD' })) {
      if (textParameter(pll.params[key],expected)!==expected) throw new Error(`Unsupported PLL ${key}; expected ${expected}.`);
    }
    if (pll.pins.CLKFB?.[0] !== pll.pins.CLKOP?.[0]) throw new Error('Supported PLL requires CLKOP feedback.');
    const clki = parameter(pll.params.CLKI_DIV, 2), fb = parameter(pll.params.CLKFB_DIV, 3);
    if (parameter(pll.params.CLKOP_DIV, 8) !== 8 || parameter(pll.params.CLKOP_CPHASE, 4) !== 4 || parameter(pll.params.CLKOP_FPHASE, 0) !== 0 || clki !== 2 || fb !== 3) throw new Error('Supported PLL profile: CLKI_DIV=2, CLKFB_DIV=3, CLKOP_DIV=8, CPHASE=4, FPHASE=0.');
    pllHz = oscHz * fb / clki;
  }
  const displays = instances.filter(item => item.type.includes('oled_gc9a01'));
  if (displays.length > 1) throw new Error('This simulator supports one OLED display.');
  const hasPins = pinNames.every(name => ports[name]?.direction === 'output' && ports[name].bits.length === 1);
  const preview = mode === 'pixel' && displays.length > 0;
  const virtualFiles = { ...files, '__gm_cells.v': primitiveModels };
  if (preview) {
    const wrapper = files['oled_gc9a01.v'];
    const definitions = wrapper?.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, '').match(/\bmodule\s+\w+/g) ?? [];
    if (definitions.length !== 1 || !/\bmodule\s+oled_gc9a01\b/.test(definitions[0])) throw new Error('Pixel Preview requires oled_gc9a01 in its own oled_gc9a01.v file. Choose SPI Simulation for other drivers.');
    virtualFiles['oled_gc9a01.v'] = pixelPreviewModel;
  }
  const connections = [];
  for (const [name, port] of Object.entries(ports)) {
    if (name === 'btn') connections.push(`.btn(buttons[${btnWidth - 1}:0])`);
    else if (name === 'clk_ext') connections.push('.clk_ext(gm_ext)');
    else if (name === 'led' || pinNames.includes(name)) connections.push(`.${name}(${name})`);
    else if (name === 'pmod_j1') connections.push(`.pmod_j1(gm_pmod[${port.bits.length - 1}:0])`);
    else if (port.direction === 'output') connections.push(`.${name}()`);
    else if (port.direction === 'input') connections.push(`.${name}(${port.bits.length}'d0)`);
    else connections.push(`.${name}()`);
  }
  const tap = preview ? displays[0].path : null;
  virtualFiles['__gm_top.v'] = `module greymecha_sim(
 input gm_osc,gm_pll,gm_ext,gm_lock, input [6:0] buttons, input pmod_resetn,
 output [7:0] led, output oled_scl,oled_sda,oled_dc,oled_cs,oled_rst,
 output [31:0] preview_sequence, output [15:0] preview_index,preview_data, output preview_resetn);
 wire [7:0] gm_pmod={7'd0,pmod_resetn};
 top dut(${connections.join(',')});
 ${ports.led ? '' : 'assign led=0;'}
 ${pinNames.filter(name => !ports[name]).map(name => `assign ${name}=${['oled_cs', 'oled_rst'].includes(name) ? 1 : 0};`).join('\n')}
 assign preview_sequence=${tap ? `${tap}.gm_sequence` : 0};
 assign preview_index=${tap ? `${tap}.gm_index` : 0};
 assign preview_data=${tap ? `${tap}.gm_data` : 0};
 assign preview_resetn=${tap ? `${tap}.resetn` : 1};
endmodule`;
  return { files: virtualFiles, mode, btnWidth, preview, hasOledPins: hasPins, hasDisplay: preview || (mode === 'spi' && hasPins), oscHz: oscillators.length ? oscHz : 0, pllHz, externalHz, hasExternal: Boolean(ports.clk_ext), hasPmod: Boolean(ports.pmod_j1), primary: plls.length ? 'gm_pll' : oscillators.length ? 'gm_osc' : 'gm_ext' };
}

export function compileModel(prepared, createCompiler, wasmModule, onLog = () => {}) {
  const diagnostics = [];
  const compiler = createCompiler({ noInitialRun: true, noExitRuntime: true,
    quit(status, error) { throw error; },
    instantiateWasm(imports, ready) { const instance = new WebAssembly.Instance(wasmModule, imports); ready(instance); return instance.exports; },
    print: line => diagnostics.push(line), printErr: line => diagnostics.push(line) });
  for (const [name, content] of Object.entries(prepared.files)) compiler.FS.writeFile(name, content);
  const sources = Object.keys(prepared.files).filter(name => name.endsWith('.v'));
  const args = ['--cc', '-O3', '--debug-check', '--language', '1364-2005', '--top-module', 'greymecha_sim', '--x-assign', '0', '-I.', '-Wno-fatal', '-Wno-DECLFILENAME', '-Wno-UNUSED', '-Wno-EOFNEWLINE', ...sources];
  try { compiler.callMain(args); } catch (error) { if (error.status !== 0) throw new Error(`Verilog compilation failed:\n${diagnostics.join('\n').slice(-7000)}`); }
  let xml;
  try { xml = compiler.FS.readFile('obj_dir/Vgreymecha_sim.xml', { encoding: 'utf8' }); }
  catch { throw new Error(`Compiler did not produce a simulation model:\n${diagnostics.join('\n').slice(-7000)}`); }
  if (diagnostics.length) onLog(diagnostics.join('\n').slice(-4000));
  // This pinned Verilator omits readmem's radix in its debug XML. Resolve it
  // from the compiler's exact source location, including included headers.
  class BoardXMLParser extends VerilogXMLParser {
    memoryCalls = [];
    visit_readmem(node) {
      if (node.attrs.hex == null) {
        const location = this.parseSourceLocation(node);
        const line = prepared.files[location.path]?.split(/\r?\n/)[location.line - 1];
        const operation = line?.slice(location.start).match(/^\$(readmemh|readmemb)\b/)?.[1];
        if (!operation) throw new Error(`Cannot resolve memory-file format at ${location.path}:${location.line}. Use a direct $readmemh or $readmemb call.`);
        node.attrs.hex = operation === 'readmemh' ? 'true' : 'false';
      }
      const call = super.visit_readmem(node);
      this.memoryCalls.push(call);
      return call;
    }
  }
  const unit = new BoardXMLParser(); unit.parse(xml);
  for (const call of unit.memoryCalls) {
    const word = call.args[1]?.dtype?.subtype;
    if (word?.left === undefined) throw new Error('Unsupported memory element type.');
    call.args.push({cvalue:Math.abs(word.left-word.right)+1,dtype:{left:31,right:0,signed:false}});
  }
  for (const dtype of Object.values(unit.dtypes)) {
    if (dtype.subtype && dtype.low && dtype.high && Math.min(dtype.low.cvalue,dtype.high.cvalue)!==0) throw new Error('Only zero-based unpacked arrays are supported by this simulation backend.');
  }
  const runtime = new PackedRuntime(unit.modules.TOP, unit.modules['@CONST-POOL@']);
  runtime.getFileData = name => {
    if (!(name in prepared.files)) throw new Error(`Missing simulation memory file ${name}.`);
    return prepared.files[name];
  };
  runtime.basefuncs.$readmem = (state, filename, memory, start, end, hex, width) => loadMemory(prepared.files, filename, memory, start, end, Boolean(hex), width);
  return new Simulation(runtime, prepared);
}

export class Simulation {
  constructor(runtime, options) {
    this.runtime = runtime; this.options = options;
    this.display = options.mode === 'spi' ? new GC9A01() : new Framebuffer();
    this.trace = new TraceCapture(signalCatalog(runtime));
    this.restart();
  }
  restart() {
    this.timePs = 0; this.cycles = 0; this.oscRises = 0; this.sequence = 0; this.resetHeld = false;
    this.display = this.options.mode === 'spi' ? new GC9A01() : new Framebuffer();
    this.clocks = [
      ['gm_osc', this.options.oscHz], ['gm_pll', this.options.pllHz], ['gm_ext', this.options.hasExternal || this.options.primary === 'gm_ext' ? this.options.externalHz : 0]
    ].filter(([, hz]) => hz > 0).map(([name, hz]) => ({ name, halfPs: 5e11 / hz, edges: 1, next: 5e11 / hz, value: 0 }));
    this.runtime.powercycle();
    Object.assign(this.runtime.state, { gm_osc: 0, gm_pll: 0, gm_ext: 0, gm_lock: 0, buttons: 127, pmod_resetn: 1 });
    this.runtime.basefuncs.$time = () => this.timePs / 1000;
    this.runtime.eval(); this.readDisplay();
    if (this.trace.enabled) this.trace.configure({ enabled: true, keys: this.trace.signals.map(signal => signal.key), generation: this.trace.generation + 1 }, this.runtime.state, this.timePs);
  }
  setInputs(buttons = 127, pmodResetn = 1) {
    Object.assign(this.runtime.state, { buttons: buttons & 127, pmod_resetn: pmodResetn ? 1 : 0 });
    this.runtime.eval(); this.readDisplay();
    if (this.trace.enabled) this.trace.sample(this.runtime.state, this.timePs);
  }
  edge() {
    const time = Math.min(...this.clocks.map(clock => clock.next));
    this.timePs = time;
    for (const clock of this.clocks) {
      if (Math.abs(clock.next - time) > 0.0001) continue;
      clock.value ^= 1; this.runtime.state[clock.name] = clock.value;
      clock.next = ++clock.edges * clock.halfPs;
      if (clock.name === 'gm_osc' && clock.value) this.oscRises++;
      if (clock.name === this.options.primary && clock.value) this.cycles++;
    }
    this.runtime.state.gm_lock = this.oscRises >= 16 ? 1 : 0;
    this.runtime.eval(); this.readDisplay();
    if (this.trace.enabled) this.trace.sample(this.runtime.state, this.timePs);
  }
  readDisplay() {
    const state = this.runtime.state;
    if (!this.options.hasDisplay) return;
    if (this.options.mode === 'spi') { this.display.sample(state); return; }
    if (!state.preview_resetn) {
      if (!this.resetHeld) this.display.clear();
      this.resetHeld = true; this.sequence = 0; return;
    }
    this.resetHeld = false;
    if (state.preview_sequence !== this.sequence) {
      this.sequence = state.preview_sequence;
      this.display.put(state.preview_index, state.preview_data);
      if (state.preview_index === 57599) this.display.frames++;
    }
  }
  advance(cycles = 1) {
    const target = this.cycles + cycles;
    while (this.cycles < target) this.edge();
  }
  snapshot(withPixels = true) {
    const state = this.runtime.state;
    const pixels = withPixels ? this.display.pixels.slice() : undefined;
    if (pixels && this.options.mode === 'spi' && (this.display.sleep || !this.display.displayOn)) {
      pixels.fill(0); for (let i = 3; i < pixels.length; i += 4) pixels[i] = 255;
    }
    return { cycles: this.cycles, seconds: this.timePs / 1e12, led: state.led & 255,
      frames: this.display.frames, writes: this.display.writes, pixels,
      pins: Object.fromEntries(pinNames.map(name => [name, Number(state[name])])),
      commands: this.display.commands ?? 0, ignored: this.display.ignored ? [...this.display.ignored] : [] };
  }
}
