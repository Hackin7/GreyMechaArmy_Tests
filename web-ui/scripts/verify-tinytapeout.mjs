import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { get } from 'svelte/store';
import { files } from '../src/lib/stores.js';
import { convertWokwiDiagram } from '../src/lib/wokwiConverter.js';

const fixture = JSON.parse(await readFile(new URL('../../wokwi/tinytapeout-template/diagram.json', import.meta.url), 'utf8'));
const convert = (diagram) => convertWokwiDiagram(diagram);
const original = convert(fixture);
assert.deepEqual(original.errors, []);
assert.equal(original.summary.format, 'Tiny Tapeout');
assert.equal(original.summary.gates, 4);
const buttonNet = new Map([...original.verilog.matchAll(/assign (net_\d+) = ~btn\[(\d)\];/g)]
  .map((match) => [Number(match[2]), match[1]]));
const inverters = new Map([...original.verilog.matchAll(/assign (net_\d+) = ~(net_\d+);/g)]
  .map((match) => [match[1], match[2]]));
const ledNet = new Map([...original.verilog.matchAll(/assign led\[(\d)\] = (net_\d+);/g)]
  .map((match) => [Number(match[1]), match[2]]));
assert.equal(buttonNet.size, 5);
for (let index = 0; index < 4; index++) {
  assert.equal(inverters.get(ledNet.get(index)), buttonNet.get(index), `OUT${index} must invert IN${index}`);
}
assert.equal(ledNet.get(4), buttonNet.get(4), 'OUT4 must follow IN4');
for (let index = 5; index < 8; index++) {
  assert.match(original.verilog, new RegExp(`assign led\\[${index}\\] = 1'b0;`));
}
assert.equal((original.verilog.match(/wokwi-gate-not/g) ?? []).length, 4);
assert.doesNotMatch(original.verilog, /OSCG oscillator|pmod_j1/);

const renamed = structuredClone(fixture);
for (const part of renamed.parts) {
  if (part.id === 'ttin') part.id = 'customInput';
  if (part.id === 'ttout') part.id = 'customOutput';
}
for (const connection of renamed.connections) {
  for (let index = 0; index < 2; index++) {
    connection[index] = connection[index].replace(/^ttin:/, 'customInput:').replace(/^ttout:/, 'customOutput:');
  }
}
assert.deepEqual(convert(renamed).errors, [], 'Tiny Tapeout blocks must be recognized by type, regardless of ID');

const edited = structuredClone(fixture);
edited.parts.push(
  { type: 'wokwi-gate-and-2', id: 'testAnd', attrs: {} },
  { type: 'wokwi-gate-buffer', id: 'testBuffer', attrs: {} },
  { type: 'wokwi-gate-xnor-2', id: 'testXnor', attrs: {} }
);
edited.connections = edited.connections.filter((connection) =>
  !['ttout:OUT0', 'ttout:OUT1', 'ttout:OUT2'].some((pin) => connection.includes(pin)));
edited.connections.push(
  ['ttin:IN0', 'testAnd:A', 'green', []],
  ['ttin:IN1', 'testAnd:B', 'green', []],
  ['testAnd:OUT', 'ttout:OUT0', 'green', []],
  ['ttin:IN1', 'testBuffer:IN', 'green', []],
  ['testBuffer:OUT', 'ttout:OUT1', 'green', []],
  ['ttin:IN2', 'testXnor:A', 'green', []],
  ['ttin:IN3', 'testXnor:B', 'green', []],
  ['testXnor:OUT', 'ttout:OUT2', 'green', []]
);
const changed = convert(edited);
assert.deepEqual(changed.errors, []);
assert.match(changed.verilog, /wokwi-gate-and-2/);
assert.match(changed.verilog, /wokwi-gate-buffer/);
assert.match(changed.verilog, /wokwi-gate-xnor-2/);
assert.equal(changed.summary.gates, 4, 'disconnected template gates should not enter the build');

const sequential = structuredClone(fixture);
sequential.parts.push(
  { type: 'wokwi-flip-flop-dsr', id: 'memory', attrs: {} },
  { type: 'wokwi-gate-not', id: 'resetInverter', attrs: {} }
);
sequential.connections = sequential.connections.filter((connection) => !connection.includes('ttout:OUT3'));
sequential.connections.push(
  ['ttin:IN0', 'memory:D', 'green', []],
  ['ttin:CLK', 'memory:CLK', 'blue', []],
  ['ttin:RST_N', 'resetInverter:IN', 'orange', []],
  ['resetInverter:OUT', 'memory:R', 'orange', []],
  ['gnd1:GND', 'memory:S', 'black', []],
  ['memory:Q', 'ttout:OUT3', 'green', []]
);
const clocked = convert(sequential);
assert.deepEqual(clocked.errors, []);
assert.equal(clocked.summary.clockHz, 10);
assert.equal(clocked.summary.resetUsed, true);
assert.match(clocked.verilog, /OSCG oscillator/);
assert.match(clocked.verilog, /pmod_j1\[0\]/);
assert.match(clocked.verilog, /posedge board_clk/);
const fasterClock = convertWokwiDiagram(sequential, { clockHz: 25 });
assert.deepEqual(fasterClock.errors, []);
assert.equal(fasterClock.summary.clockHz, 25);
assert.notEqual(fasterClock.verilog, clocked.verilog);
assert.ok(convertWokwiDiagram(sequential, { clockHz: '' }).errors.some((error) => error.includes('clock speed')));

const ignored = structuredClone(fixture);
ignored.connections = ignored.connections.filter((connection) => !connection.includes('not1:IN'));
ignored.connections.push(['ttin:IN5', 'not1:IN', 'green', []]);
assert.ok(convert(ignored).errors.some((error) => error.includes('ignored ttin:IN5')));
const disconnected = structuredClone(fixture);
disconnected.connections = disconnected.connections.filter((connection) => !connection.includes('ttout:OUT0'));
assert.match(convert(disconnected).verilog, /assign led\[0\] = 1'b0;/);
const unsupported = structuredClone(fixture);
unsupported.parts.push({ type: 'unsupported-logic', id: 'unknownGate', attrs: {} });
unsupported.connections.push(['unknownGate:OUT', 'ttout:OUT0', 'green', []]);
assert.ok(convert(unsupported).errors.some((error) => error.includes('unknownGate:OUT')));
const undriven = structuredClone(fixture);
undriven.connections = undriven.connections.filter((connection) => !connection.includes('not1:IN'));
assert.ok(convert(undriven).errors.some((error) => error.includes('not1:IN')));
const multipleDrivers = structuredClone(fixture);
multipleDrivers.connections.push(['not2:OUT', 'ttout:OUT0', 'green', []]);
assert.ok(convert(multipleDrivers).errors.some((error) => error.includes('Multiple drivers')));
const cycle = structuredClone(undriven);
cycle.connections.push(['not1:OUT', 'not1:IN', 'green', []]);
assert.ok(convert(cycle).errors.some((error) => error.includes('Combinational loop')));

const messages = [];
globalThis.self = { postMessage(message) { messages.push(message); } };
await import('../src/lib/synthesisWorker.js');
for (const [runId, label, converted] of [[40, 'template', original], [41, 'edited gates', changed], [42, 'clock and reset', clocked]]) {
  const oldLog = console.log;
  const oldInfo = console.info;
  const oldWarn = console.warn;
  try {
    console.log = console.info = console.warn = () => {};
    await self.onmessage({ data: { type: 'SYNTHESIZE', runId, files: { ...get(files), 'top.v': converted.verilog } } });
  } finally {
    console.log = oldLog;
    console.info = oldInfo;
    console.warn = oldWarn;
  }
  const result = messages.filter((message) => message.runId === runId);
  const error = result.find((message) => message.type === 'ERROR');
  if (error) {
    const log = result.filter((message) => message.type === 'LOG').map((message) => message.message).join('');
    throw new Error(`${label}: ${error.stage}: ${error.error}\n${log.slice(-4000)}`);
  }
  for (const type of ['LOGICAL_READY', 'MAPPED_READY', 'ROUTED_READY', 'DONE']) {
    assert.ok(result.some((message) => message.type === type), `${label}: missing ${type}`);
  }
  console.log(`${label}: converted and built through Yosys, nextpnr, ecppack`);
}
console.log('Tiny Tapeout input validation: ignored input, unsupported part, missing input, multiple drivers, and cycle rejected');
