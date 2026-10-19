import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { createRequire } from 'node:module';
import { build } from 'esbuild';
import { performance } from 'node:perf_hooks';
import './verify-simulator-assets.mjs';

globalThis.require = createRequire(import.meta.url);
globalThis.__dirname = new URL('../public/simulator/', import.meta.url).pathname;
await mkdir(new URL('../.sim-test/', import.meta.url), { recursive: true });
await build({ stdin: { contents: `export * from './src/lib/simulator/engine.js'; export * from './src/lib/simulator/display.js'; export {oledSimple,oledDemo} from './src/lib/oledPreset.js'; export {convertWokwiDiagram} from './src/lib/wokwiConverter.js'; import {files} from './src/lib/stores.js'; import {get} from 'svelte/store'; export const defaultDesign=get(files);`, resolveDir: process.cwd() },
  outfile: '.sim-test/engine.mjs', bundle: true, platform: 'node', format: 'esm', packages: 'external',
  plugins: [{ name: 'verilog-raw', setup(builder) {
    builder.onResolve({ filter: /\?raw$/ }, args => ({ path: path.resolve(args.resolveDir, args.path.slice(0, -4)), namespace: 'raw' }));
    builder.onLoad({ filter: /.*/, namespace: 'raw' }, async args => ({ contents: await readFile(args.path, 'utf8'), loader: 'text' }));
  }}] });
const { prepareSimulation, compileModel, oledSimple, oledDemo, GC9A01, rgb565, convertWokwiDiagram, defaultDesign } = await import('../.sim-test/engine.mjs');
const { default: createCompiler } = await import('../public/simulator/verilator.mjs');
const wasmModule = new WebAssembly.Module(await readFile(new URL('../public/simulator/verilator_bin.wasm', import.meta.url)));
const output = console.log;
async function compile(files, mode = 'pixel') {
  console.log = console.info = console.warn = () => {};
  try {
    const prepared = await prepareSimulation(files, mode);
    return compileModel(prepared, createCompiler, wasmModule);
  } finally { console.log = console.info = console.warn = output; }
}

const start = performance.now();
const starter=await compile(defaultDesign);starter.advance(1024);
assert.equal(starter.runtime.state['greymecha_sim$dut$counter'],1024);
assert.equal(starter.options.btnWidth,7);
output('Unmodified default starter oscillator and counter passed.');
const basicSource = `module top(input clk_ext,input [6:0] btn,output [7:0] led);
reg [7:0] count=0; always @(posedge clk_ext) count<=count+1;
assign led=count ^ {1'b0,~btn}; endmodule`;
const basic = await compile({ 'top.v': basicSource });
basic.advance(10); assert.equal(basic.snapshot(false).led, 10);
basic.setInputs(126); assert.equal(basic.snapshot(false).led, 11);
basic.restart(); assert.equal(basic.cycles, 0);
output('Counter, button input, and restart passed.');

// Compare the browser runtime with native Icarus on identical clock/input edges.
const source = `module top(input clk_ext,input [6:0] btn,output [7:0] led);
reg [2:0] q=0; reg [7:0] rom[0:3];
initial $readmemh("native.mem",rom);
always @(posedge clk_ext or negedge btn[6])
 if(!btn[6]) q<=0; else q<={q[1:0],btn[0]^btn[1]};
assign led=rom[btn[3:2]] ^ {5'b0,q}; endmodule`;
const nativeSim = await compile({ 'top.v': source, 'native.mem': '12\n34\n56\n78\n' });
const stimuli = [127,126,125,123,111,95,63,127,124,112,100,126,125,127];
const actual = stimuli.map(value => { nativeSim.setInputs(value); nativeSim.advance(1); return nativeSim.snapshot(false).led; });
await writeFile('.sim-test/native.v', source);
await writeFile('.sim-test/native.mem', '12\n34\n56\n78\n');
await writeFile('.sim-test/native_tb.v', `module tb;reg clk_ext=0;reg [6:0] btn=127;wire [7:0] led; top dut(clk_ext,btn,led);
initial begin ${stimuli.map(value => `btn=7'd${value}; #5 clk_ext=1; #1 $display("TRACE %d",led); #4 clk_ext=0;`).join('\n')} $finish;end endmodule`);
const nativeDir = path.resolve('.sim-test');
const linuxPath = value => value.replace(/\\/g, '/').replace(/^([A-Z]):/i, (_, drive) => `/mnt/${drive.toLowerCase()}`);
function native(tool, args) {
  return execFileSync(process.platform === 'win32' ? 'wsl' : tool,
    process.platform === 'win32' ? ['--exec', tool, ...args.map(linuxPath)] : args,
    { cwd: nativeDir, encoding: 'utf8', timeout: 60000 });
}
native('iverilog', ['-g2005', '-o', path.join(nativeDir,'reference.vvp'), path.join(nativeDir,'native_tb.v'), path.join(nativeDir,'native.v')]);
const expected = [...native('vvp', [path.join(nativeDir,'reference.vvp')]).matchAll(/TRACE\s+(\d+)/g)].map(match => Number(match[1]));
assert.deepEqual(actual, expected);
output('Native Icarus parity: asynchronous reset, flip-flops, ROM, and input changes passed.');
for(const fixture of ['greymecha-compact','greymecha-circuit']) {
  const result=convertWokwiDiagram(await readFile(new URL(`../../wokwi/${fixture}/diagram.json`,import.meta.url),'utf8'),{clockHz:100000});
  assert.deepEqual(result.errors,[]);
  const simulated=await compile({'top.v':result.verilog});
  const values=[];
  for(let mask=0;mask<32;mask++) { simulated.setInputs(mask);simulated.advance(2048);values.push(simulated.snapshot(false).led); }
  await writeFile('.sim-test/native.v',result.verilog);
  await writeFile('.sim-test/native_tb.v',`module OSCG(output OSC);parameter DIV="5";assign OSC=tb.clk;endmodule
module tb;reg clk=0;always #5 clk=~clk;reg [4:0] btn=31;wire [7:0] led;top dut(.btn(btn),.led(led));
initial begin ${Array.from({length:32},(_,mask)=>`btn=5'd${mask};repeat(2048) @(posedge clk);#1 $display("TRACE %d",led);`).join('\n')} $finish;end endmodule`);
  native('iverilog',['-g2005','-o',path.join(nativeDir,'reference.vvp'),path.join(nativeDir,'native_tb.v'),path.join(nativeDir,'native.v')]);
  const reference=[...native('vvp',[path.join(nativeDir,'reference.vvp')]).matchAll(/TRACE\s+(\d+)/g)].map(match=>Number(match[1]));
  assert.deepEqual(values,reference,`${fixture} differs from native Icarus`);
  output(`${fixture}: all 32 input patterns and clocked behavior match native Icarus.`);
}

const tt = convertWokwiDiagram(await readFile(new URL('../../wokwi/tinytapeout-template/diagram.json', import.meta.url), 'utf8'));
assert.deepEqual(tt.errors, []);
const ttSim = await compile({ 'top.v': tt.verilog });
for (let mask=0; mask<128; mask++) {
  ttSim.setInputs(mask); assert.equal(ttSim.snapshot(false).led, (mask & 15) | ((~mask) & 112));
}
output('Tiny Tapeout import: all 128 button combinations passed.');

const ddr = await compile({ 'top.v': `module top(input [6:0] btn,output [7:0] led);
wire clk,q; OSCG #(.DIV("6")) osc(.OSC(clk));
ODDRX1F ddr(.SCLK(clk),.RST(~btn[6]),.D0(btn[0]),.D1(btn[1]),.Q(q));
assign led={7'b0,q}; endmodule` });
ddr.setInputs(126); ddr.edge(); assert.equal(ddr.snapshot(false).led, 0);
ddr.edge(); assert.equal(ddr.snapshot(false).led, 1);
ddr.setInputs(62); assert.equal(ddr.snapshot(false).led, 0);
output('ODDRX1F rising/falling edges and reset passed.');

// Panel protocol tests exercise byte sampling, windows, color order, reset and
// partial transfers independently of the Verilog driver.
const panel = new GC9A01();
function byte(value, dc) {
  for(let bit=7;bit>=0;bit--) {
    const pins={oled_rst:1,oled_cs:0,oled_dc:dc,oled_sda:(value>>bit)&1};
    panel.sample({...pins,oled_scl:0}); panel.sample({...pins,oled_scl:1}); panel.sample({...pins,oled_scl:0});
  }
}
function cmd(value,args=[]) { byte(value,0); args.forEach(value=>byte(value,1)); }
cmd(0x11);cmd(0x29);cmd(0x36,[8]);cmd(0x3a,[5]);cmd(0x2a,[0,0,0,1]);cmd(0x2b,[0,0,0,0]);cmd(0x2c);
for(const value of [0xf8,0x00,0x07,0xe0]) byte(value,1);
assert.deepEqual([...panel.pixels.slice(0,8)],[255,0,0,255,0,255,0,255]);assert.equal(panel.frames,1);
cmd(0x36,[0x48]);cmd(0x2a,[0,0,0,0]);cmd(0x2c);byte(0,1);byte(0x1f,1);
assert.deepEqual([...panel.pixels.slice(239*4,240*4)],[0,0,255,255]);
cmd(0x20);assert.deepEqual([...panel.pixels.slice(239*4,240*4)],[255,255,0,255]);
cmd(0x21);assert.deepEqual([...panel.pixels.slice(239*4,240*4)],[0,0,255,255]);
const writes=panel.writes;
panel.sample({oled_rst:1,oled_cs:0,oled_dc:1,oled_scl:1,oled_sda:1});
panel.sample({oled_rst:1,oled_cs:1,oled_dc:1,oled_scl:0,oled_sda:1});
assert.equal(panel.writes,writes);
panel.sample({oled_rst:0});assert.equal(panel.writes,0);assert.equal(panel.sleep,true);
output('GC9A01 SPI commands, window wrapping, RGB565, orientation, partial transfers and reset passed.');

function verifyFrame(sim, label, expectedPixel) {
  const pixels=sim.snapshot().pixels;
  for(let i=0;i<57600;i++) {
    const expected=rgb565(expectedPixel(i%240,Math.floor(i/240)));
    for(let n=0;n<3;n++) assert.equal(pixels[i*4+n],expected[n],`${label} pixel ${i}, channel ${n}`);
  }
}
function frames(sim,count=2) {
  const target=sim.display.frames+count;
  while(sim.display.frames<target) sim.advance(4096);
}
const image=[];let imageAddress=0;
for(const token of (await readFile(new URL('../src/lib/presets/oled-fast/stonks.mem',import.meta.url),'utf8')).trim().split(/\s+/)) {
  if(token.startsWith('@')) imageAddress=parseInt(token.slice(1),16);
  else image[imageAddress++]=parseInt(token,16);
}
for (const [name, files] of [['OLED', oledSimple], ['OLED Advanced', oledDemo]]) {
  const sim = await compile(files);
  output(`${name}: compiled, ${JSON.stringify(sim.options, (k,v)=> k==='files' ? undefined : v)}`);
  sim.advance(240_000);
  const snap = sim.snapshot();
  assert.ok(snap.frames >= 1, `${name} did not render a frame`);
  // The user's literal is 6'b11111 (31/63 green), not 6'b111111.
  assert.deepEqual([...snap.pixels.slice(0, 4)], name === 'OLED' ? [0,125,0,255] : [255,255,255,255]);
  output(`${name}: ${snap.frames} frames; ${sim.cycles} cycles.`);
  assert.ok(Math.abs(sim.oscRises/sim.cycles-2/3)<0.01,'PLL/OSCG clock ratio changed');
  if(name==='OLED Advanced') {
    sim.setInputs(126);sim.advance(5000);frames(sim);
    verifyFrame(sim,'FULL image',(x,y)=>image[Math.floor(y*4/15)*96+Math.floor(x*2/5)]);
    for(const [aspect, pixel] of [
      [1,(x,y)=>y<40||y>=200?0:image[Math.floor((y-40)*2/5)*96+Math.floor(x*2/5)]],
      [2,(x,y)=>x<24||x>=216||y<56||y>=184?0:image[Math.floor((y-56)/2)*96+Math.floor((x-24)/2)]]
    ]) {
      sim.setInputs(94);sim.advance(5000);sim.setInputs(126);sim.advance(5000);frames(sim);
      assert.equal(sim.snapshot(false).led&3,aspect);verifyFrame(sim,`aspect ${aspect}`,pixel);
    }
    for(const [button,color] of [[1,0xf800],[2,0x07e0],[3,0x001f],[4,0xfe19]]) {
      sim.setInputs(127^(1<<button));sim.advance(5000);frames(sim);verifyFrame(sim,`color button ${button}`,()=>color);
    }
    output('Advanced preview: every pixel matches the image in all three aspect modes and all color buttons.');
  }
  sim.setInputs(63);sim.advance(1024);assert.equal(sim.display.writes,0);assert.equal(sim.display.frames,0);
}
const { 'stonks.mem': unusedImage, ...missingMemory } = oledDemo;
await assert.rejects(()=>compile(missingMemory), /stonks.mem/);
await assert.rejects(()=>compile({'top.v':'module top(output [7:0] led); MISSING x(led); endmodule'}), /failed|not part/);
const { 'oled_gc9a01.v': originalWrapper, ...missingWrapper } = oledSimple;
await assert.rejects(()=>compile({...missingWrapper, 'renamed_driver.v':originalWrapper}), /own oled_gc9a01.v/);
output(`Simulator smoke tests passed in ${((performance.now()-start)/1000).toFixed(1)}s.`);
