import assert from 'node:assert/strict';
import { TraceCapture, signalCatalog, mergeTrace, formatTraceValue } from '../src/lib/simulator/trace.js';

const globals = {
  buttons: { dtype: { left: 6, right: 0 }, origName: 'buttons', isInput: true },
  led: { dtype: { left: 7, right: 0 }, origName: 'led' },
  wide: { dtype: { left: 63, right: 0 }, origName: 'dut$wide' },
  signed: { dtype: { left: 31, right: 0, signed: true }, origName: 'signed' },
  reverse: { dtype: { left: 0, right: 7 }, origName: 'reverse' },
  '__Vtemp': { dtype: { left: 0, right: 0 } },
  'top$__Vdly': { dtype: { left: 7, right: 0 } },
  rom: { dtype: { subtype: {}, low: {}, high: {} } },
};
const state = { buttons: 127, led: 0, wide: 0xfedcba9876543210n, signed: -1, reverse: 255, __Vtemp: 0, 'top$__Vdly': 0, rom: [0] };
const catalog = signalCatalog({ globals, state });
assert.deepEqual(catalog.map(signal => signal.key).sort(), ['buttons', 'led', 'reverse', 'signed', 'wide']);
assert.equal(catalog.find(signal => signal.key === 'reverse').width, 8);
assert.equal(signalCatalog({ globals: { 'greymecha_sim$dut$u_block$q': { dtype: { left: 3, right: 0 }, origName: 'q' } },
  state: { 'greymecha_sim$dut$u_block$q': 1 } })[0].label, 'top.u_block.q');
const trace = new TraceCapture(catalog, 3);
trace.sample(state, 0); assert.equal(trace.length, 0, 'closed capture must do no trace work');
trace.configure({ enabled: true, keys: ['buttons', 'led', 'wide', 'signed'], generation: 1 }, state, 0);
trace.sample(state, 1000); assert.equal(trace.length, 1, 'unchanged edges must not consume records');
state.buttons = 126; trace.sample(state, 1000);
state.buttons = 125; trace.sample(state, 1000);
let update = trace.snapshot();
assert.deepEqual(update.records.map(record => record.timePs), [0, 1000, 1000]);
assert.deepEqual(update.records.map(record => record.sequence), [0, 1, 2]);
assert.equal(update.records[0].values[2], 'fedcba9876543210');
assert.equal(update.records[0].values[3], 'ffffffff');
assert.equal(formatTraceValue('ffffffff', catalog.find(signal => signal.key === 'signed'), 10), '-1');
assert.equal(formatTraceValue('fedcba9876543210', catalog.find(signal => signal.key === 'wide'), 10), '18364758544493064720');
const first = update;
state.led = 1; trace.sample(state, 1666.6666666667);
update = trace.snapshot(2);
assert.equal(update.dropped, 1); assert.equal(update.oldestSequence, 1);
assert.equal(update.records.length, 1);
const merged = mergeTrace(first, update);
assert.deepEqual(merged.records.map(record => record.sequence), [1, 2, 3]);
assert.equal(merged.records[0].values[0], '7e', 'rollover must retain the full baseline');
assert.equal(mergeTrace(merged, update).records.length, 3, 'duplicate batches must be harmless');
trace.configure({ enabled: true, keys: ['led'], generation: 2 }, state, 2000);
const reset = mergeTrace(merged, trace.snapshot());
assert.equal(reset.records.length, 1); assert.equal(reset.generation, 2);
assert.equal(mergeTrace(reset, first), reset, 'old capture generations must be rejected');
assert.throws(() => trace.configure({ enabled: true, keys: ['missing'], generation: 3 }, state, 0), /unavailable/);
const many = Array.from({ length: 33 }, (_, index) => ({ key: `q${index}`, width: 1 }));
assert.throws(() => new TraceCapture(many).configure({ enabled: true, keys: many.map(signal => signal.key), generation: 3 }, state, 0), /at most 32/);
trace.configure({ enabled: false, keys: [], generation: 4 }, state, 3000);
state.led = 2; trace.sample(state, 4000); assert.equal(trace.length, 0);
console.log('Waveform catalog, two-state values, same-time ordering, wide/signed buses, bounded rollover, deltas and stale generations passed.');
