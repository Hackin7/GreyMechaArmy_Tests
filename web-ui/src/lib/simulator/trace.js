// Settled, two-state traces. Nothing is sampled while capture is disabled.
export const TRACE_CAPACITY = 8192;
export const TRACE_SIGNAL_LIMIT = 32;

export function signalCatalog(runtime) {
  return Object.entries(runtime.globals).flatMap(([key, variable]) => {
    const type = variable.dtype;
    if (!type || !Number.isInteger(type.left) || !Number.isInteger(type.right) || variable.isParam ||
        key.split('$').some(part => part.startsWith('__V')) || key.includes('@')) return [];
    const width = Math.abs(type.left - type.right) + 1;
    if (typeof runtime.state[key] !== 'number' && typeof runtime.state[key] !== 'bigint') return [];
    let label = (key.includes('$') ? key : variable.origName || key).replaceAll('$', '.').replace(/^greymecha_sim\.dut(?:\.|$)/, 'top.');
    if (key === 'buttons') label = 'btn';
    if (key === 'pmod_resetn') label = 'pmod_j1[0]';
    return [{ key, label, width, signed: Boolean(type.signed), input: Boolean(variable.isInput) }];
  }).sort((a, b) => a.label.localeCompare(b.label) || a.key.localeCompare(b.key));
}

function normalize(value, width) {
  if (width <= 32 && typeof value === 'number') return width === 32 ? value >>> 0 : (value >>> 0) % 2 ** width;
  return BigInt.asUintN(width, BigInt(value));
}

export class TraceCapture {
  constructor(catalog, capacity = TRACE_CAPACITY) {
    this.catalog = catalog; this.capacity = capacity; this.enabled = false;
    this.records = new Array(capacity); this.length = 0; this.head = 0; this.sequence = 0;
    this.dropped = 0; this.signals = []; this.generation = 0;
  }
  configure({ enabled, keys = [], generation }, state, timePs) {
    const unique = [...new Set(keys)];
    if (unique.length > TRACE_SIGNAL_LIMIT) throw new Error(`Select at most ${TRACE_SIGNAL_LIMIT} waveform signals.`);
    const signals = unique.map(key => {
      const signal = this.catalog.find(item => item.key === key);
      if (!signal) throw new Error(`Waveform signal is unavailable: ${key}`);
      return signal;
    });
    this.enabled = Boolean(enabled); this.signals = signals; this.generation = generation;
    this.records.fill(undefined); this.length = 0; this.head = 0; this.sequence = 0; this.dropped = 0;
    this.previous = undefined; this.endPs = timePs;
    if (this.enabled) this.sample(state, timePs);
  }
  sample(state, timePs) {
    if (!this.enabled) return;
    this.endPs = timePs;
    const values = this.signals.map(signal => normalize(state[signal.key], signal.width));
    if (this.previous && values.every((value, i) => value === this.previous[i])) return;
    this.previous = values;
    const record = { sequence: this.sequence++, timePs, values };
    if (this.length === this.capacity) { this.records[this.head] = record; this.head = (this.head + 1) % this.capacity; this.dropped++; }
    else { this.records[(this.head + this.length) % this.capacity] = record; this.length++; }
  }
  snapshot(afterSequence = -1) {
    const records = [];
    for (let i = 0; i < this.length; i++) {
      const record = this.records[(this.head + i) % this.capacity];
      if (record.sequence > afterSequence) records.push({ ...record, values: record.values.map(value => value.toString(16)) });
    }
    return { generation: this.generation, signals: this.signals, records, endPs: this.endPs,
      oldestSequence: this.records[this.head]?.sequence ?? 0, dropped: this.dropped };
  }
}

export function mergeTrace(previous, update) {
  if (previous && update.generation < previous.generation) return previous;
  if (!previous || previous.generation !== update.generation) return update;
  const last = previous.records.at(-1)?.sequence ?? -1;
  return { ...update, records: [...previous.records.filter(record => record.sequence >= update.oldestSequence),
    ...update.records.filter(record => record.sequence > last)] };
}

export function formatTraceValue(hex, signal, radix = 16) {
  if (hex === undefined) return '—';
  let value = BigInt(`0x${hex}`);
  if (radix === 10 && signal.signed) value = BigInt.asIntN(signal.width, value);
  return radix === 16 ? `0x${hex.toUpperCase().padStart(Math.ceil(signal.width / 4), '0')}` : value.toString(10);
}
