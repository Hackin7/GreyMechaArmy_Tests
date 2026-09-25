import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { get } from 'svelte/store';
import { files } from '../src/lib/stores.js';
import { convertWokwiDiagram } from '../src/lib/wokwiConverter.js';

const examples = ['greymecha-compact', 'greymecha-circuit'];
const messages = [];
globalThis.self = { postMessage(message) { messages.push(message); } };
await import('../src/lib/synthesisWorker.js');

for (const [index, example] of examples.entries()) {
  const text = await readFile(new URL(`../../wokwi/${example}/diagram.json`, import.meta.url), 'utf8');
  const diagram = JSON.parse(text);
  const converted = convertWokwiDiagram(diagram);
  assert.deepEqual(converted.errors, [], `${example}: conversion errors`);
  assert.match(converted.verilog, /module top\(input \[4:0\] btn, output \[7:0\] led\)/);
  assert.match(converted.verilog, /OSCG oscillator/);
  assert.equal(converted.summary.flipFlops, 2);

  const invalid = structuredClone(diagram);
  invalid.parts.push({ type: 'unknown', id: 'bad' });
  assert.ok(convertWokwiDiagram(invalid).errors.some((error) => error.includes('bad')));
  assert.ok(convertWokwiDiagram('{').errors.some((error) => error.includes('Invalid JSON')));
  const secondClock = structuredClone(diagram);
  secondClock.parts.push({ type: 'wokwi-clock-generator', id: 'clock2' });
  assert.ok(convertWokwiDiagram(secondClock).errors.some((error) => error.includes('Only one')));
  const badPin = structuredClone(diagram);
  badPin.connections.push(['memory0:MISSING', 'clock:CLK', []]);
  assert.ok(convertWokwiDiagram(badPin).errors.some((error) => error.includes('MISSING')));
  const undriven = structuredClone(diagram);
  undriven.connections = undriven.connections.filter((connection) => connection[1] !== 'and0:B');
  assert.ok(convertWokwiDiagram(undriven).errors.some((error) => error.includes('and0:B')));
  const multipleDrivers = structuredClone(diagram);
  multipleDrivers.connections.push(['not0:OUT', 'not1:OUT', 'green', []]);
  assert.ok(convertWokwiDiagram(multipleDrivers).errors.some((error) => error.includes('Multiple drivers')));
  const loop = structuredClone(undriven);
  loop.connections.push(['and0:OUT', 'and0:B', 'green', []]);
  assert.ok(convertWokwiDiagram(loop).errors.some((error) => error.includes('Combinational loop')));
  const badClock = structuredClone(diagram);
  badClock.connections = badClock.connections.filter((connection) => connection[1] !== 'memory0:CLK');
  badClock.connections.push(['not0:OUT', 'memory0:CLK', 'yellow', []]);
  assert.ok(convertWokwiDiagram(badClock).errors.some((error) => error.includes('memory0:CLK')));
  const unusedLed = structuredClone(diagram);
  unusedLed.connections = unusedLed.connections.filter((connection) => connection[1] !== (example === 'greymecha-compact' ? 'badge:LED7' : 'led7:A'));
  const unusedResult = convertWokwiDiagram(unusedLed);
  assert.deepEqual(unusedResult.errors, []);
  assert.match(unusedResult.verilog, /assign led\[7\] = 1'b0;/);
  if (example === 'greymecha-circuit') {
    const noPullup = structuredClone(diagram);
    noPullup.connections = noPullup.connections.filter((connection) => connection[1] !== 'btn0:1.l');
    assert.ok(convertWokwiDiagram(noPullup).errors.some((error) => error.includes('btn0:1.l')));
  }

  const runId = index + 1;
  const originals = get(files);
  const originalLog = console.log;
  const originalInfo = console.info;
  const originalWarn = console.warn;
  try {
    console.log = console.info = console.warn = () => {};
    await self.onmessage({ data: { type: 'SYNTHESIZE', runId, files: { ...originals, 'top.v': converted.verilog } } });
  } finally {
    console.log = originalLog;
    console.info = originalInfo;
    console.warn = originalWarn;
  }
  const output = messages.filter((message) => message.runId === runId);
  const error = output.find((message) => message.type === 'ERROR');
  if (error) {
    const logs = output.filter((message) => message.type === 'LOG').map((message) => message.message).join('');
    throw new Error(`${example}: ${error.stage}: ${error.error}\n${logs.slice(-5000)}`);
  }
  for (const type of ['MAPPED_READY', 'ROUTED_READY', 'DONE']) {
    assert.ok(output.some((message) => message.type === type), `${example}: missing ${type}`);
  }
  console.log(`${example}: converted and built through Yosys, nextpnr, ecppack`);
}

// The ECP5 flip-flop supports one active asynchronous control; reject two.
const resetDiagram = JSON.parse(await readFile(new URL('../../wokwi/greymecha-compact/diagram.json', import.meta.url), 'utf8'));
resetDiagram.parts.push({ type: 'wokwi-gate-not', id: 'not3', top: 250, left: 220, attrs: {} });
resetDiagram.connections = resetDiagram.connections.filter((connection) => connection[1] !== 'memory1:S');
resetDiagram.connections.push(['badge:BTN3_N', 'not3:IN', 'green', []], ['not3:OUT', 'memory1:S', 'green', []]);
const withSet = convertWokwiDiagram(resetDiagram);
assert.ok(withSet.errors.some((error) => error.includes('memory1:S') && error.includes('memory1:R')));
console.log('Dynamic DSR set/reset: rejected with pin-specific error');

const setOnlyDiagram = structuredClone(resetDiagram);
setOnlyDiagram.connections = setOnlyDiagram.connections.filter((connection) => connection[1] !== 'memory1:R');
setOnlyDiagram.connections.push(['ground0:GND', 'memory1:R', 'black', []]);
const setOnly = convertWokwiDiagram(setOnlyDiagram);
assert.deepEqual(setOnly.errors, []);
const previousLog = console.log;
console.log = () => {};
try {
  await self.onmessage({ data: { type: 'SYNTHESIZE', runId: 3, files: { ...get(files), 'top.v': setOnly.verilog } } });
} finally {
  console.log = previousLog;
}
const setOnlyError = messages.find((message) => message.runId === 3 && message.type === 'ERROR');
if (setOnlyError) {
  const logs = messages.filter((message) => message.runId === 3 && message.type === 'LOG').map((message) => message.message).join('');
  throw new Error(`Asynchronous set: ${setOnlyError.stage}: ${setOnlyError.error}\n${logs.slice(-3000)}`);
}
assert.ok(messages.some((message) => message.runId === 3 && message.type === 'DONE'));
console.log('Asynchronous set: converted and built');
