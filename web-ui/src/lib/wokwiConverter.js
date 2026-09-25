const GATES = {
  'wokwi-gate-buffer': { inputs: ['IN'], output: 'OUT', expression: ([a]) => a },
  'wokwi-gate-not': { inputs: ['IN'], output: 'OUT', expression: ([a]) => `~${a}` },
  'wokwi-gate-and-2': { inputs: ['A', 'B'], output: 'OUT', expression: ([a, b]) => `${a} & ${b}` },
  'wokwi-gate-or-2': { inputs: ['A', 'B'], output: 'OUT', expression: ([a, b]) => `${a} | ${b}` },
  'wokwi-gate-xor-2': { inputs: ['A', 'B'], output: 'OUT', expression: ([a, b]) => `${a} ^ ${b}` },
  'wokwi-gate-nand-2': { inputs: ['A', 'B'], output: 'OUT', expression: ([a, b]) => `~(${a} & ${b})` },
  'wokwi-gate-xnor-2': { inputs: ['A', 'B'], output: 'OUT', expression: ([a, b]) => `~(${a} ^ ${b})` },
  'wokwi-mux-2': { inputs: ['A', 'B', 'SEL'], output: 'OUT', expression: ([a, b, select]) => `${select} ? ${b} : ${a}` }
};

const FLOPS = {
  'wokwi-flip-flop-d': ['D', 'CLK', 'Q', 'NOTQ'],
  'wokwi-flip-flop-dsr': ['D', 'CLK', 'S', 'R', 'Q', 'NOTQ']
};

const FIXED_PINS = {
  'wokwi-vcc': ['VCC'],
  'wokwi-gnd': ['GND'],
  'wokwi-clock-generator': ['CLK'],
  'wokwi-pushbutton': ['1.l', '1.r', '2.l', '2.r'],
  'wokwi-led': ['A', 'C'],
  'wokwi-resistor': ['1', '2'],
  'wokwi-text': [],
  'chip-greymecha': [
    ...Array.from({ length: 5 }, (_, index) => `BTN${index}_N`),
    ...Array.from({ length: 8 }, (_, index) => `LED${index}`)
  ]
};

const BADGE_CLOCK_HZ = 62_000_000;
const validId = /^[a-zA-Z][a-zA-Z0-9_-]*$/;

function pinList(type) {
  if (GATES[type]) return [...GATES[type].inputs, GATES[type].output];
  if (FLOPS[type]) return FLOPS[type];
  return FIXED_PINS[type];
}

function parseFrequency(raw) {
  const match = String(raw ?? '').trim().match(/^(\d+(?:\.\d+)?)\s*([kKmM]?)$/);
  if (!match) return null;
  const value = Number(match[1]) * ({ '': 1, k: 1_000, m: 1_000_000 }[match[2].toLowerCase()]);
  return Number.isFinite(value) && value >= 1 && value <= 100_000 ? value : null;
}

/** Convert a restricted Wokwi digital diagram to a Yosys-readable top module. */
export function convertWokwiDiagram(input, { clockHz: requestedClockHz = 10 } = {}) {
  const errors = [];
  let diagram;
  try {
    diagram = typeof input === 'string' ? JSON.parse(input) : input;
  } catch (error) {
    return { verilog: null, errors: [`Invalid JSON: ${error.message}`], summary: null };
  }
  if (!diagram || typeof diagram !== 'object' || diagram.version !== 1 || !Array.isArray(diagram.parts) || !Array.isArray(diagram.connections)) {
    return { verilog: null, errors: ['Expected Wokwi diagram.json version 1 with parts and connections arrays.'], summary: null };
  }
  const clockHz = parseFrequency(requestedClockHz);
  if (clockHz === null) {
    return { verilog: null, errors: ['Badge clock speed must be from 1 Hz to 100 kHz.'], summary: null };
  }
  if (diagram.parts.some((part) => part?.type === 'board-tt-block-input' || part?.type === 'board-tt-block-input-8' || part?.type === 'board-tt-block-output')) {
    return convertTinyTapeoutDiagram(diagram, clockHz);
  }

  const parts = new Map();
  for (const part of diagram.parts) {
    if (!part || typeof part.id !== 'string' || !validId.test(part.id) || typeof part.type !== 'string') {
      errors.push('A part has a missing or invalid id or type.');
      continue;
    }
    if (parts.has(part.id)) errors.push(`Duplicate part id "${part.id}".`);
    else if (!pinList(part.type)) errors.push(`Unsupported part "${part.id}" (${part.type}).`);
    else parts.set(part.id, part);
  }
  if (errors.length) return { verilog: null, errors, summary: null };

  const parent = new Map();
  function find(endpoint) {
    if (!parent.has(endpoint)) parent.set(endpoint, endpoint);
    const current = parent.get(endpoint);
    if (current !== endpoint) parent.set(endpoint, find(current));
    return parent.get(endpoint);
  }
  function join(a, b) {
    const ra = find(a);
    const rb = find(b);
    if (ra !== rb) parent.set(rb, ra);
  }
  function endpointParts(endpoint) {
    if (typeof endpoint !== 'string') return null;
    const colon = endpoint.indexOf(':');
    if (colon < 1) return null;
    const id = endpoint.slice(0, colon);
    const pin = endpoint.slice(colon + 1);
    const part = parts.get(id);
    if (!part || !pinList(part.type).includes(pin)) return null;
    return { id, pin, part };
  }
  for (const [index, connection] of diagram.connections.entries()) {
    if (!Array.isArray(connection) || connection.length < 2) {
      errors.push(`Connection ${index + 1} is malformed.`);
      continue;
    }
    const a = endpointParts(connection[0]);
    const b = endpointParts(connection[1]);
    if (!a || !b) {
      errors.push(`Connection ${index + 1} has an unknown pin: ${String(connection[0])} → ${String(connection[1])}.`);
      continue;
    }
    join(`${a.id}:${a.pin}`, `${b.id}:${b.pin}`);
  }
  if (errors.length) return { verilog: null, errors, summary: null };

  // The two pins on either side of a pushbutton are the same contact.
  for (const part of parts.values()) {
    if (part.type === 'wokwi-pushbutton') {
      join(`${part.id}:1.l`, `${part.id}:1.r`);
      join(`${part.id}:2.l`, `${part.id}:2.r`);
    }
  }

  const endpoints = new Map();
  for (const part of parts.values()) {
    for (const pin of pinList(part.type)) {
      const endpoint = `${part.id}:${pin}`;
      const root = find(endpoint);
      if (!endpoints.has(root)) endpoints.set(root, []);
      endpoints.get(root).push(endpoint);
    }
  }
  const roots = [...endpoints.keys()].sort((a, b) => a.localeCompare(b));
  const names = new Map(roots.map((root, index) => [root, `net_${index}`]));
  const rootOf = (part, pin) => find(`${part.id}:${pin}`);
  const signal = (part, pin) => names.get(rootOf(part, pin));
  const drivers = new Map();
  const addDriver = (part, pin, kind, value) => {
    const root = rootOf(part, pin);
    if (!drivers.has(root)) drivers.set(root, []);
    drivers.get(root).push({ part, pin, kind, value });
  };

  const compactBadges = [...parts.values()].filter((part) => part.type === 'chip-greymecha');
  const standardButtons = [...parts.values()].filter((part) => part.type === 'wokwi-pushbutton' && /^btn[0-4]$/.test(part.id));
  const standardLeds = [...parts.values()].filter((part) => part.type === 'wokwi-led' && /^led[0-7]$/.test(part.id));
  if (compactBadges.length > 1 || (compactBadges.length && (standardButtons.length || standardLeds.length))) {
    errors.push('Use one chip-greymecha badge or named btn0–btn4/led0–led7 parts, not both in one diagram.');
  }
  if (!compactBadges.length && !standardButtons.length) errors.push('No GreyMecha button inputs were found.');
  if (!compactBadges.length && !standardLeds.length) errors.push('No GreyMecha LED outputs were found.');
  for (const part of parts.values()) {
    if (part.type === 'wokwi-pushbutton' && !standardButtons.includes(part)) errors.push(`Button "${part.id}" must be named btn0–btn4.`);
    if (part.type === 'wokwi-led' && !standardLeds.includes(part)) errors.push(`LED "${part.id}" must be named led0–led7.`);
  }
  if (!compactBadges.length) {
    for (const button of standardButtons) {
      const groundNet = endpoints.get(rootOf(button, '2.l')) ?? [];
      if (!groundNet.some((endpoint) => endpoint.endsWith(':GND') && parts.get(endpoint.split(':')[0])?.type === 'wokwi-gnd')) {
        errors.push(`Button ${button.id}:2.l must connect to GND for active-low input.`);
      }
      const buttonNet = endpoints.get(rootOf(button, '1.l')) ?? [];
      const pullup = buttonNet.map((endpoint) => endpointParts(endpoint)).find((item) => item?.part.type === 'wokwi-resistor');
      if (!pullup) {
        errors.push(`Button ${button.id}:1.l needs a pull-up resistor to VCC.`);
      } else {
        const otherPin = pullup.pin === '1' ? '2' : '1';
        const supplyNet = endpoints.get(rootOf(pullup.part, otherPin)) ?? [];
        if (!supplyNet.some((endpoint) => endpoint.endsWith(':VCC') && parts.get(endpoint.split(':')[0])?.type === 'wokwi-vcc')) {
          errors.push(`Button ${button.id}:1.l pull-up resistor ${pullup.id} must connect to VCC.`);
        }
      }
    }
    for (const led of standardLeds) {
      const cathodeNet = endpoints.get(rootOf(led, 'C')) ?? [];
      if (!cathodeNet.some((endpoint) => endpoint.endsWith(':GND') && parts.get(endpoint.split(':')[0])?.type === 'wokwi-gnd')) {
        errors.push(`LED ${led.id}:C must connect to GND.`);
      }
    }
  }
  for (const index of [0, 1, 2, 3, 4]) {
    const part = compactBadges[0] ?? standardButtons.find((item) => item.id === `btn${index}`);
    if (part) addDriver(part, compactBadges.length ? `BTN${index}_N` : '1.l', 'button', index);
  }
  for (const part of parts.values()) {
    if (part.type === 'wokwi-vcc') addDriver(part, 'VCC', 'constant', 1);
    if (part.type === 'wokwi-gnd') addDriver(part, 'GND', 'constant', 0);
    if (part.type === 'wokwi-clock-generator') addDriver(part, 'CLK', 'clock', null);
    if (GATES[part.type]) addDriver(part, 'OUT', 'gate', null);
    if (FLOPS[part.type]) {
      addDriver(part, 'Q', 'flop', false);
      addDriver(part, 'NOTQ', 'flop', true);
    }
  }
  for (const [root, list] of drivers) {
    if (list.length > 1) errors.push(`Multiple drivers on net ${endpoints.get(root).join(', ')}.`);
  }

  function requireDriven(part, pin) {
    const root = rootOf(part, pin);
    if (!drivers.has(root)) errors.push(`Input ${part.id}:${pin} is not driven.`);
    return drivers.get(root)?.[0] ?? null;
  }
  const gates = [...parts.values()].filter((part) => GATES[part.type]);
  const flops = [...parts.values()].filter((part) => FLOPS[part.type]);
  const clocks = [...parts.values()].filter((part) => part.type === 'wokwi-clock-generator');
  if (clocks.length > 1) errors.push('Only one Wokwi clock generator is supported.');
  if (flops.length && clocks.length !== 1) errors.push('Flip-flops require one Wokwi clock generator.');
  for (const gate of gates) {
    for (const pin of GATES[gate.type].inputs) requireDriven(gate, pin);
  }
  for (const flop of flops) {
    for (const pin of FLOPS[flop.type].filter((pin) => !['CLK', 'Q', 'NOTQ'].includes(pin))) requireDriven(flop, pin);
    const driver = requireDriven(flop, 'CLK');
    if (driver && driver.kind !== 'clock') errors.push(`Clock input ${flop.id}:CLK must be driven by the Wokwi clock generator.`);
    if (flop.type === 'wokwi-flip-flop-dsr') {
      const set = drivers.get(rootOf(flop, 'S'))?.[0];
      const reset = drivers.get(rootOf(flop, 'R'))?.[0];
      const inactive = (control) => control?.kind === 'constant' && control.value === 0;
      if (set && reset && !inactive(set) && !inactive(reset)) {
        errors.push(`Flip-flop ${flop.id}:S and ${flop.id}:R cannot both be active controls on ECP5; tie one to GND.`);
      }
    }
  }

  const ledSource = (index) => {
    const part = compactBadges[0] ?? standardLeds.find((item) => item.id === `led${index}`);
    if (!part) return null;
    const pin = compactBadges.length ? `LED${index}` : 'A';
    return drivers.has(rootOf(part, pin)) ? { part, pin } : null;
  };
  const ledSources = Array.from({ length: 8 }, (_, index) => ledSource(index));

  // A gate may depend on another gate, but a flip-flop output is a cycle break.
  const gateById = new Map(gates.map((gate) => [gate.id, gate]));
  const visiting = new Set();
  const visited = new Set();
  function visit(gate) {
    if (visiting.has(gate.id)) {
      errors.push(`Combinational loop includes gate "${gate.id}".`);
      return;
    }
    if (visited.has(gate.id)) return;
    visiting.add(gate.id);
    for (const pin of GATES[gate.type].inputs) {
      const driver = drivers.get(rootOf(gate, pin))?.[0];
      if (driver?.kind === 'gate' && gateById.has(driver.part.id)) visit(driver.part);
    }
    visiting.delete(gate.id);
    visited.add(gate.id);
  }
  for (const gate of gates) visit(gate);
  if (errors.length) return { verilog: null, errors: [...new Set(errors)], summary: null };

  const lines = [
    '// Generated from a Wokwi diagram. Edit the diagram and re-import to regenerate.',
    'module top(input [4:0] btn, output [7:0] led);',
    ...roots.map((root) => `  wire ${names.get(root)};`)
  ];
  const flopName = new Map(flops.map((flop, index) => [flop.id, `q_${index}`]));
  if (clocks.length) {
    const halfPeriod = Math.max(2, Math.round(BADGE_CLOCK_HZ / (2 * clockHz)));
    const width = Math.max(1, Math.ceil(Math.log2(halfPeriod)));
    lines.push(
      `  // Nominal ${clockHz} Hz from an approximately ${BADGE_CLOCK_HZ} Hz oscillator; actual rate varies.`,
      '  wire osc_clk;',
      '  OSCG oscillator (.OSC(osc_clk));',
      '  defparam oscillator.DIV = "5";',
      `  reg [${width - 1}:0] clock_count = 0;`,
      '  reg board_clk = 0;',
      '  always @(posedge osc_clk) begin',
      `    if (clock_count == ${halfPeriod - 1}) begin`,
      '      clock_count <= 0;',
      '      board_clk <= ~board_clk;',
      '    end else clock_count <= clock_count + 1\'b1;',
      '  end'
    );
  }
  for (const root of roots) {
    const driver = drivers.get(root)?.[0];
    if (!driver) continue;
    const target = names.get(root);
    if (driver.kind === 'button') lines.push(`  // ${driver.part.id}:${driver.pin} -> badge button ${driver.value}`, `  assign ${target} = btn[${driver.value}];`);
    if (driver.kind === 'constant') lines.push(`  // ${driver.part.id}:${driver.pin}`, `  assign ${target} = 1'b${driver.value};`);
    if (driver.kind === 'clock') lines.push(`  // ${driver.part.id}:${driver.pin}`, `  assign ${target} = board_clk;`);
    if (driver.kind === 'gate') {
      const gate = driver.part;
      const definition = GATES[gate.type];
      const expression = definition.expression(definition.inputs.map((pin) => signal(gate, pin)));
      lines.push(`  // ${gate.id}: ${gate.type}`, `  assign ${target} = ${expression};`);
    }
    if (driver.kind === 'flop') lines.push(`  assign ${target} = ${driver.value ? '~' : ''}${flopName.get(driver.part.id)};`);
  }
  for (const flop of flops) {
    const q = flopName.get(flop.id);
    const setControl = flop.type === 'wokwi-flip-flop-dsr' ? drivers.get(rootOf(flop, 'S'))?.[0] : null;
    const resetControl = flop.type === 'wokwi-flip-flop-dsr' ? drivers.get(rootOf(flop, 'R'))?.[0] : null;
    const setOnly = setControl && !(setControl.kind === 'constant' && setControl.value === 0)
      && resetControl?.kind === 'constant' && resetControl.value === 0;
    lines.push(`  // ${flop.id}: ${flop.type}`, `  reg ${q}${setOnly ? '' : ' = 0'};`);
    if (flop.type === 'wokwi-flip-flop-d') {
      lines.push(`  always @(posedge board_clk) ${q} <= ${signal(flop, 'D')};`);
    } else {
      const set = drivers.get(rootOf(flop, 'S'))?.[0];
      const reset = drivers.get(rootOf(flop, 'R'))?.[0];
      if (reset?.kind === 'constant' && reset.value === 0 && set?.kind === 'constant' && set.value === 0) {
        lines.push(`  always @(posedge board_clk) ${q} <= ${signal(flop, 'D')};`);
      } else if (set?.kind === 'constant' && set.value === 0) {
        lines.push(`  always @(posedge board_clk or posedge ${signal(flop, 'R')}) begin`,
          `    if (${signal(flop, 'R')}) ${q} <= 1'b0;`,
          `    else ${q} <= ${signal(flop, 'D')};`, '  end');
      } else {
        lines.push(`  always @(posedge board_clk or posedge ${signal(flop, 'S')}) begin`,
          `    if (${signal(flop, 'S')}) ${q} <= 1'b1;`,
          `    else ${q} <= ${signal(flop, 'D')};`, '  end');
      }
    }
  }
  for (const [index, source] of ledSources.entries()) {
    if (source) lines.push(`  // ${source.part.id}:${source.pin} -> badge LED ${index}`);
    lines.push(`  assign led[${index}] = ${source ? signal(source.part, source.pin) : "1'b0"};`);
  }
  lines.push('endmodule', '');
  return {
    verilog: lines.join('\n'),
    errors: [],
    summary: {
      gates: gates.length,
      flipFlops: flops.length,
      buttons: compactBadges.length ? 5 : standardButtons.length,
      leds: compactBadges.length ? 8 : standardLeds.length,
      clockHz: clocks.length ? clockHz : null,
      approximateClock: clocks.length > 0
    }
  };
}

const TT_INPUT_TYPES = new Set(['board-tt-block-input', 'board-tt-block-input-8']);
const TT_INPUT_PINS = [
  ...Array.from({ length: 8 }, (_, index) => `IN${index}`),
  ...Array.from({ length: 8 }, (_, index) => `EXTIN${index}`),
  'CLK', 'RST_N', 'EXTCLK', 'EXTRST_N'
];
const TT_OUTPUT_PINS = [
  ...Array.from({ length: 8 }, (_, index) => `OUT${index}`),
  ...Array.from({ length: 8 }, (_, index) => `EXTOUT${index}`)
];
const TT_DISPLAY_PINS = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'DP', 'COM.1', 'COM.2'];

function tinyTapeoutPins(type) {
  if (TT_INPUT_TYPES.has(type)) return TT_INPUT_PINS;
  if (type === 'board-tt-block-output') return TT_OUTPUT_PINS;
  if (type === 'wokwi-dip-switch-8') return Array.from({ length: 8 }, (_, index) => [
    `${index + 1}a`, `${index + 1}b`
  ]).flat();
  if (type === 'wokwi-slide-switch') return ['1', '2', '3'];
  if (type === 'wokwi-7segment') return TT_DISPLAY_PINS;
  return pinList(type);
}

function convertTinyTapeoutDiagram(diagram, clockHz) {
  const errors = [];
  const parts = new Map();
  for (const part of diagram.parts) {
    if (!part || typeof part.id !== 'string' || !validId.test(part.id) || typeof part.type !== 'string') {
      errors.push('A part has a missing or invalid id or type.');
    } else if (parts.has(part.id)) {
      errors.push(`Duplicate part id "${part.id}".`);
    } else {
      parts.set(part.id, part);
    }
  }
  const inputBlocks = [...parts.values()].filter((part) => TT_INPUT_TYPES.has(part.type));
  const outputBlocks = [...parts.values()].filter((part) => part.type === 'board-tt-block-output');
  if (inputBlocks.length !== 1 || outputBlocks.length !== 1) {
    errors.push('Tiny Tapeout diagrams need exactly one input block and one output block.');
  }
  if (errors.length) return { verilog: null, errors, summary: null };
  const inputBlock = inputBlocks[0];
  const outputBlock = outputBlocks[0];

  const parent = new Map();
  const allEndpoints = new Set();
  function find(endpoint) {
    if (!parent.has(endpoint)) parent.set(endpoint, endpoint);
    const current = parent.get(endpoint);
    if (current !== endpoint) parent.set(endpoint, find(current));
    return parent.get(endpoint);
  }
  function join(a, b) {
    const left = find(a);
    const right = find(b);
    if (left !== right) parent.set(right, left);
  }
  function parseEndpoint(endpoint) {
    if (typeof endpoint !== 'string') return null;
    const separator = endpoint.indexOf(':');
    if (separator < 1) return null;
    const part = parts.get(endpoint.slice(0, separator));
    const pin = endpoint.slice(separator + 1);
    if (!part || !pin || (tinyTapeoutPins(part.type) && !tinyTapeoutPins(part.type).includes(pin))) return null;
    return { part, pin };
  }
  for (const [index, connection] of diagram.connections.entries()) {
    if (!Array.isArray(connection) || connection.length < 2) {
      errors.push(`Connection ${index + 1} is malformed.`);
      continue;
    }
    const left = parseEndpoint(connection[0]);
    const right = parseEndpoint(connection[1]);
    if (!left || !right) {
      errors.push(`Connection ${index + 1} has an unknown pin: ${String(connection[0])} → ${String(connection[1])}.`);
      continue;
    }
    allEndpoints.add(connection[0]);
    allEndpoints.add(connection[1]);
    join(connection[0], connection[1]);
  }
  if (errors.length) return { verilog: null, errors, summary: null };

  for (const part of parts.values()) {
    if (part.type === 'wokwi-pushbutton') {
      join(`${part.id}:1.l`, `${part.id}:1.r`);
      join(`${part.id}:2.l`, `${part.id}:2.r`);
    }
    if (part === inputBlock || part === outputBlock || GATES[part.type] || FLOPS[part.type]) {
      for (const pin of tinyTapeoutPins(part.type)) allEndpoints.add(`${part.id}:${pin}`);
    }
  }
  const endpoints = new Map();
  for (const endpoint of allEndpoints) {
    const root = find(endpoint);
    if (!endpoints.has(root)) endpoints.set(root, []);
    endpoints.get(root).push(endpoint);
  }
  const rootOf = (part, pin) => find(`${part.id}:${pin}`);
  const drivers = new Map();
  function addDriver(part, pin, kind, value = null) {
    const root = rootOf(part, pin);
    if (!drivers.has(root)) drivers.set(root, []);
    drivers.get(root).push({ part, pin, kind, value });
  }
  for (let index = 0; index < 8; index++) {
    addDriver(inputBlock, `IN${index}`, index < 5 ? 'button' : 'ignored-input', index);
  }
  addDriver(inputBlock, 'CLK', 'clock');
  addDriver(inputBlock, 'RST_N', 'reset');
  for (const part of parts.values()) {
    if (part.type === 'wokwi-vcc') addDriver(part, 'VCC', 'constant', 1);
    if (part.type === 'wokwi-gnd') addDriver(part, 'GND', 'constant', 0);
    if (part.type === 'wokwi-clock-generator') addDriver(part, 'CLK', 'simulator-clock');
    if (GATES[part.type]) addDriver(part, 'OUT', 'gate');
    if (FLOPS[part.type]) {
      addDriver(part, 'Q', 'flop', false);
      addDriver(part, 'NOTQ', 'flop', true);
    }
  }

  const outputRoots = Array.from({ length: 8 }, (_, index) => rootOf(outputBlock, `OUT${index}`));
  const work = outputRoots.map((root, index) => ({ root, use: 'output', label: `${outputBlock.id}:OUT${index}` }));
  const visitedUses = new Set();
  const activeRoots = new Set();
  const activeGates = new Map();
  const activeFlops = new Map();
  const reportOnce = new Set();
  function report(message) {
    if (!reportOnce.has(message)) {
      reportOnce.add(message);
      errors.push(message);
    }
  }
  while (work.length) {
    const { root, use, label } = work.shift();
    const visitKey = `${root}|${use}|${label}`;
    if (visitedUses.has(visitKey)) continue;
    visitedUses.add(visitKey);
    activeRoots.add(root);
    const attached = endpoints.get(root) ?? [];
    const unsupported = attached.find((endpoint) => !tinyTapeoutPins(parts.get(endpoint.split(':')[0])?.type));
    if (unsupported) report(`Unsupported part ${unsupported} is connected to active Tiny Tapeout logic.`);
    const sources = drivers.get(root) ?? [];
    if (sources.length > 1) {
      report(`Multiple drivers on net ${attached.join(', ')}.`);
      continue;
    }
    const source = sources[0];
    if (!source) {
      const bareOutput = use === 'output' && attached.every((endpoint) => endpoint.startsWith(`${outputBlock.id}:OUT`));
      if (!bareOutput) report(`Input ${label} is not driven by supported logic.`);
      continue;
    }
    if (source.kind === 'ignored-input') {
      const directOutput = use === 'output' && attached.every((endpoint) =>
        endpoint.startsWith(`${outputBlock.id}:OUT`) || endpoint === `${inputBlock.id}:IN${source.value}`);
      if (!directOutput) report(`Input ${label} uses ignored ${inputBlock.id}:IN${source.value}. Only IN0–IN4 are available on the badge.`);
      continue;
    }
    if (source.kind === 'simulator-clock') {
      report(`Input ${label} uses the Wokwi clock generator directly; use ${inputBlock.id}:CLK for badge logic.`);
      continue;
    }
    if (use === 'flop-clock' && source.kind !== 'clock') {
      report(`Clock input ${label} must be driven by ${inputBlock.id}:CLK.`);
    }
    if (source.kind === 'gate' && !activeGates.has(source.part.id)) {
      const gate = source.part;
      activeGates.set(gate.id, gate);
      for (const pin of GATES[gate.type].inputs) {
        work.push({ root: rootOf(gate, pin), use: 'gate-input', label: `${gate.id}:${pin}` });
      }
    }
    if (source.kind === 'flop' && !activeFlops.has(source.part.id)) {
      const flop = source.part;
      activeFlops.set(flop.id, flop);
      for (const pin of FLOPS[flop.type].filter((item) => !['Q', 'NOTQ'].includes(item))) {
        work.push({ root: rootOf(flop, pin), use: pin === 'CLK' ? 'flop-clock' : 'flop-input', label: `${flop.id}:${pin}` });
      }
    }
  }

  const gates = [...activeGates.values()].sort((a, b) => a.id.localeCompare(b.id));
  const flops = [...activeFlops.values()].sort((a, b) => a.id.localeCompare(b.id));
  const driverOf = (part, pin) => drivers.get(rootOf(part, pin))?.[0];
  for (const flop of flops) {
    if (flop.type !== 'wokwi-flip-flop-dsr') continue;
    const set = driverOf(flop, 'S');
    const reset = driverOf(flop, 'R');
    const inactive = (control) => control?.kind === 'constant' && control.value === 0;
    if (set && reset && !inactive(set) && !inactive(reset)) {
      report(`Flip-flop ${flop.id}:S and ${flop.id}:R cannot both be active controls on ECP5; tie one to GND.`);
    }
  }
  const visiting = new Set();
  const visited = new Set();
  function visitGate(gate) {
    if (visiting.has(gate.id)) {
      report(`Combinational loop includes gate "${gate.id}".`);
      return;
    }
    if (visited.has(gate.id)) return;
    visiting.add(gate.id);
    for (const pin of GATES[gate.type].inputs) {
      const source = driverOf(gate, pin);
      if (source?.kind === 'gate') visitGate(source.part);
    }
    visiting.delete(gate.id);
    visited.add(gate.id);
  }
  for (const gate of gates) visitGate(gate);

  const clockUsed = [...activeRoots].some((root) => drivers.get(root)?.[0]?.kind === 'clock');
  const resetUsed = [...activeRoots].some((root) => drivers.get(root)?.[0]?.kind === 'reset');
  if (clockUsed) {
    const generators = [...parts.values()].filter((part) => part.type === 'wokwi-clock-generator');
    if (generators.length !== 1) report('Badge clock logic requires exactly one Wokwi clock generator in the template.');
  }
  if (errors.length) return { verilog: null, errors, summary: null };

  const roots = [...activeRoots].sort((a, b) =>
    (endpoints.get(a)?.slice().sort()[0] ?? a).localeCompare(endpoints.get(b)?.slice().sort()[0] ?? b));
  const names = new Map(roots.map((root, index) => [root, `net_${index}`]));
  const signal = (part, pin) => names.get(rootOf(part, pin));
  const flopName = new Map(flops.map((flop, index) => [flop.id, `q_${index}`]));
  const lines = [
    '// Generated from a Tiny Tapeout Wokwi diagram.',
    `module top(input [4:0] btn, ${resetUsed ? 'input [7:0] pmod_j1, ' : ''}output [7:0] led);`,
    ...roots.map((root) => `  wire ${names.get(root)};`)
  ];
  if (clockUsed) {
    const halfPeriod = Math.max(2, Math.round(BADGE_CLOCK_HZ / (2 * clockHz)));
    const width = Math.max(1, Math.ceil(Math.log2(halfPeriod)));
    lines.push(
      `  // Nominal ${clockHz} Hz from an approximately ${BADGE_CLOCK_HZ} Hz oscillator; actual rate varies.`,
      '  wire osc_clk;',
      '  OSCG oscillator (.OSC(osc_clk));',
      '  defparam oscillator.DIV = "5";',
      `  reg [${width - 1}:0] clock_count = 0;`,
      '  reg board_clk = 0;',
      '  always @(posedge osc_clk) begin',
      `    if (clock_count == ${halfPeriod - 1}) begin`,
      '      clock_count <= 0;',
      '      board_clk <= ~board_clk;',
      "    end else clock_count <= clock_count + 1'b1;",
      '  end'
    );
  }
  for (const root of roots) {
    const source = drivers.get(root)?.[0];
    if (!source) continue;
    const target = names.get(root);
    if (source.kind === 'button') lines.push(`  // ${inputBlock.id}:IN${source.value} -> pressed badge button`, `  assign ${target} = ~btn[${source.value}];`);
    if (source.kind === 'ignored-input') lines.push(`  assign ${target} = 1'b0; // ignored IN${source.value}`);
    if (source.kind === 'constant') lines.push(`  assign ${target} = 1'b${source.value};`);
    if (source.kind === 'clock') lines.push(`  assign ${target} = board_clk;`);
    if (source.kind === 'reset') lines.push(`  assign ${target} = pmod_j1[0]; // active-low reset`);
    if (source.kind === 'gate') {
      const definition = GATES[source.part.type];
      lines.push(`  // ${source.part.id}: ${source.part.type}`,
        `  assign ${target} = ${definition.expression(definition.inputs.map((pin) => signal(source.part, pin)))};`);
    }
    if (source.kind === 'flop') lines.push(`  assign ${target} = ${source.value ? '~' : ''}${flopName.get(source.part.id)};`);
  }
  for (const flop of flops) {
    const q = flopName.get(flop.id);
    const set = flop.type === 'wokwi-flip-flop-dsr' ? driverOf(flop, 'S') : null;
    const reset = flop.type === 'wokwi-flip-flop-dsr' ? driverOf(flop, 'R') : null;
    const setOnly = set && !(set.kind === 'constant' && set.value === 0)
      && reset?.kind === 'constant' && reset.value === 0;
    lines.push(`  // ${flop.id}: ${flop.type}`, `  reg ${q}${setOnly ? '' : ' = 0'};`);
    if (flop.type === 'wokwi-flip-flop-d' || (set?.kind === 'constant' && set.value === 0 && reset?.kind === 'constant' && reset.value === 0)) {
      lines.push(`  always @(posedge board_clk) ${q} <= ${signal(flop, 'D')};`);
    } else if (set?.kind === 'constant' && set.value === 0) {
      lines.push(`  always @(posedge board_clk or posedge ${signal(flop, 'R')}) begin`,
        `    if (${signal(flop, 'R')}) ${q} <= 1'b0;`,
        `    else ${q} <= ${signal(flop, 'D')};`, '  end');
    } else {
      lines.push(`  always @(posedge board_clk or posedge ${signal(flop, 'S')}) begin`,
        `    if (${signal(flop, 'S')}) ${q} <= 1'b1;`,
        `    else ${q} <= ${signal(flop, 'D')};`, '  end');
    }
  }
  for (const [index, root] of outputRoots.entries()) {
    const source = drivers.get(root)?.[0];
    lines.push(`  // ${outputBlock.id}:OUT${index} -> badge LED ${index}`,
      `  assign led[${index}] = ${source && source.kind !== 'ignored-input' ? names.get(root) : "1'b0"};`);
  }
  lines.push('endmodule', '');
  return {
    verilog: lines.join('\n'),
    errors: [],
    summary: {
      format: 'Tiny Tapeout',
      gates: gates.length,
      flipFlops: flops.length,
      buttons: 5,
      leds: 8,
      clockHz: clockUsed ? clockHz : null,
      approximateClock: clockUsed,
      resetUsed,
      ignoredInputs: [5, 6, 7]
    }
  };
}
