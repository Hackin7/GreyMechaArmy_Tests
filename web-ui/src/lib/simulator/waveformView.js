// Timestamp-aware Svelte adapter for the pinned GPL-3.0 8bitworkshop scope core.
// We retain its navigation/cursor model and replace uniform-sample drawing with
// settled digital traces and bus bands on the simulator's physical time axis.
import { WaveformCore } from '../../../vendor/8bitworkshop/waveformcore.ts';
import { formatTraceValue } from './trace.js';

export function formatTime(ps, precision = 10) {
  const [scale, unit] = Math.abs(ps) >= 1e12 ? [1e12, 's'] : Math.abs(ps) >= 1e9 ? [1e9, 'ms'] : Math.abs(ps) >= 1e6 ? [1e6, 'µs'] : Math.abs(ps) >= 1e3 ? [1e3, 'ns'] : [1, 'ps'];
  return `${Number((ps / scale).toPrecision(precision))} ${unit}`;
}

export function recordAt(trace, timePs, sequence) {
  const records = trace?.records ?? [];
  if (sequence !== undefined) {
    const exact = records.find(record => record.sequence === sequence);
    if (exact) return exact;
  }
  let low = 0, high = records.length;
  while (low < high) { const middle = (low + high) >>> 1; if (records[middle].timePs <= timePs) low = middle + 1; else high = middle; }
  return records[Math.max(0, low - 1)];
}

export class WaveformCanvas extends WaveformCore {
  constructor(canvas, changed = () => {}) {
    super({ getSignalMetadata: () => [], getSignalData: () => [], setSignalValue() {} });
    this.canvas = canvas; this.changed = changed; this.trace = { records: [], signals: [], endPs: 0 };
    this.meta = []; this.labelWidth = 170; this.pageWidth = 400; this.zoom = .0004;
    this.clockMax = 0; this.t0 = 0; this.tsel = -1; this.follow = true; this.radix = 16;
    this.setClocksPerPage();
  }
  recreate() { this.refresh(); }
  promptValue() { return Promise.resolve(null); }
  isEditable() { return false; }
  selectionChanged() { this.changed(); }
  roundT(time) { return Math.max(this.start, Math.min(this.clockMax, time)); }
  get start() { return this.trace.records[0]?.timePs ?? 0; }
  get span() { return this.pageWidth / this.zoom; }
  setTrace(trace, radix = this.radix) {
    this.radix = radix;
    const reset = this.trace.generation !== trace?.generation;
    this.trace = trace ?? { records: [], signals: [], endPs: 0 };
    this.meta = this.trace.signals; this.clockMax = this.trace.endPs;
    if (reset) { this.tsel = -1; this.selectedSequence = undefined; }
    if (this.follow) this.t0 = Math.max(this.start, this.clockMax - this.span);
    else this.t0 = Math.max(this.start, Math.min(this.t0, this.clockMax));
    if ((this.tsel >= 0 && this.tsel < this.start) || (this.selectedSequence !== undefined && this.selectedSequence < (this.trace.records[0]?.sequence ?? 0))) {
      this.tsel = this.start; this.selectedSequence = this.trace.records[0]?.sequence;
    }
    this.refresh();
  }
  resize(width) {
    this.width = Math.max(260, width); this.labelWidth = Math.min(190, this.width * .43);
    this.pageWidth = this.width - this.labelWidth - 12; this.setClocksPerPage(); this.refresh();
  }
  setZoom(zoom) {
    const anchor = this.tsel >= 0 ? this.tsel : this.t0 + this.span / 2;
    this.zoom = Math.max(1e-12, Math.min(1e6, zoom)); this.setClocksPerPage();
    this.t0 = Math.max(this.start, Math.min(this.clockMax, anchor - this.span / 2));
    this.follow = false; this.refresh(); this.changed();
  }
  setOrgTime(time) { this.t0 = Math.max(this.start, Math.min(this.clockMax, time)); this.refresh(); }
  fit() {
    this.zoom = this.pageWidth / Math.max(1, this.clockMax - this.start);
    this.t0 = this.start; this.follow = false; this.setClocksPerPage(); this.refresh(); this.changed();
  }
  selectTime(time) {
    this.selectedSequence = undefined; this.follow = false;
    this.setSelTime(time); this.changed();
  }
  selectRecord(direction) {
    const records = this.trace.records; if (!records.length) return;
    const current = recordAt(this.trace, this.tsel < 0 ? this.clockMax : this.tsel, this.selectedSequence);
    const index = records.indexOf(current);
    const record = records[Math.max(0, Math.min(records.length - 1, index + direction))];
    this.selectedSequence = record.sequence; this.follow = false; this.setSelTime(record.timePs);
  }
  pan(fraction) { this.follow = false; this.setOrgTime(this.t0 + this.span * fraction); this.changed(); }
  refresh() {
    if (!this.canvas || !this.width) return;
    const canvas = this.canvas, ratio = globalThis.devicePixelRatio || 1;
    const height = 30 + Math.max(1, this.meta.length) * 44;
    canvas.width = Math.round(this.width * ratio); canvas.height = Math.round(height * ratio);
    canvas.style.height = `${height}px`;
    const ctx = canvas.getContext('2d'); ctx.scale(ratio, ratio);
    ctx.fillStyle = '#1e1e1e'; ctx.fillRect(0, 0, this.width, height);
    ctx.font = '11px Consolas, monospace';
    ctx.fillStyle = '#858585'; ctx.fillText(`Start ${formatTime(this.t0)}`, 7, 16, this.labelWidth - 12);
    const x = time => this.labelWidth + (time - this.t0) * this.zoom;
    const cursor = recordAt(this.trace, this.tsel < 0 ? this.clockMax : this.tsel, this.selectedSequence);
    for (let tick = 0; tick <= 4; tick++) {
      const time = this.t0 + this.span * tick / 4, px = x(time);
      ctx.strokeStyle = '#333'; ctx.beginPath(); ctx.moveTo(px, 25); ctx.lineTo(px, height); ctx.stroke();
      ctx.fillStyle = '#858585'; ctx.textAlign = tick === 4 ? 'right' : tick === 0 ? 'left' : 'center'; ctx.fillText(`+${formatTime(time - this.t0, 5)}`, px + (tick === 0 ? 3 : 0), 16);
    }
    ctx.textAlign = 'left';
    this.meta.forEach((signal, row) => {
      const y = 30 + row * 44, records = this.trace.records;
      ctx.strokeStyle = '#333'; ctx.beginPath(); ctx.moveTo(0, y + 42); ctx.lineTo(this.width, y + 42); ctx.stroke();
      ctx.save(); ctx.beginPath(); ctx.rect(0, y, this.labelWidth - 5, 42); ctx.clip();
      ctx.fillStyle = '#d4d4d4'; ctx.fillText(signal.label, 7, y + 15);
      ctx.fillStyle = '#9cdcfe'; ctx.fillText(`${signal.width}b  ${formatTraceValue(cursor?.values[row], signal, this.radix)}`, 7, y + 32); ctx.restore();
      ctx.save(); ctx.beginPath(); ctx.rect(this.labelWidth, y, this.pageWidth, 42); ctx.clip();
      const initial = recordAt(this.trace, this.t0);
      let from = initial ? records.indexOf(initial) : 0;
      for (let i = from; i < records.length;) {
        const record = records[i];
        let end = i + 1;
        while (end < records.length && records[end].values[row] === record.values[row]) end++;
        const next = records[end];
        const left = Math.max(this.labelWidth, x(record.timePs)), right = Math.min(this.width - 12, x(next?.timePs ?? this.clockMax));
        if (left > this.width) break;
        if (right < this.labelWidth || right < left) { i = end; continue; }
        const value = record.values[row];
        ctx.strokeStyle = '#4fc1ff'; ctx.fillStyle = '#9cdcfe'; ctx.beginPath();
        if (signal.width === 1) {
          const level = value === '0' ? y + 32 : y + 10;
          if (i > 0 && records[i - 1].values[row] !== value) { ctx.moveTo(left, y + 10); ctx.lineTo(left, y + 32); }
          ctx.moveTo(left, level); ctx.lineTo(right, level);
        } else {
          ctx.moveTo(left, y + 21); ctx.lineTo(left + Math.min(3, (right - left) / 2), y + 9); ctx.lineTo(right - Math.min(3, (right - left) / 2), y + 9);
          ctx.lineTo(right, y + 21); ctx.lineTo(right - Math.min(3, (right - left) / 2), y + 33); ctx.lineTo(left + Math.min(3, (right - left) / 2), y + 33); ctx.closePath();
          const text = formatTraceValue(value, signal, this.radix);
          if (right - left > ctx.measureText(text).width + 10) ctx.fillText(text, left + 5, y + 25);
        }
        ctx.stroke();
        i = end;
      }
      ctx.restore();
    });
    if (this.tsel >= this.t0 && this.tsel <= this.t0 + this.span) {
      ctx.strokeStyle = '#ce9178'; ctx.beginPath(); ctx.moveTo(x(this.tsel), 22); ctx.lineTo(x(this.tsel), height); ctx.stroke();
    }
  }
}
