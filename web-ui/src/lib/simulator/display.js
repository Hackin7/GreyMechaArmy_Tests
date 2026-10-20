export const WIDTH = 240;
export const HEIGHT = 240;

export function rgb565(value, swap = false) {
  let r = (value >>> 11) & 31;
  const g = (value >>> 5) & 63;
  let b = value & 31;
  if (swap) [r, b] = [b, r];
  return [Math.round(r * 255 / 31), Math.round(g * 255 / 63), Math.round(b * 255 / 31)];
}

export class Framebuffer {
  constructor() { this.pixels = new Uint8ClampedArray(WIDTH * HEIGHT * 4); this.frames = 0; this.writes = 0; this.clear(); }
  clear() { this.pixels.fill(0); for (let i = 3; i < this.pixels.length; i += 4) this.pixels[i] = 255; this.frames = 0; this.writes = 0; }
  put(index, value, swap = false, invert = false) {
    if (index < 0 || index >= WIDTH * HEIGHT) return;
    const color = rgb565(value, swap);
    for (let n = 0; n < 3; n++) this.pixels[index * 4 + n] = invert ? 255 - color[n] : color[n];
    this.writes++;
  }
}

// Digital GC9A01 model. Decode the actual mode-0, MSB-first SPI pin traffic.
export class GC9A01 extends Framebuffer {
  constructor() { super(); this.reset(); }
  reset() {
    this.clear(); this.command = 0; this.args = []; this.bits = 0; this.byte = 0;
    this.prevClock = 0; this.prevCs = 1; this.resetHeld = false;
    this.x0 = 0; this.x1 = 239; this.y0 = 0; this.y1 = 239; this.x = 0; this.y = 0;
    this.high = null; this.madctl = 0; this.colmod = 5; this.sleep = true; this.displayOn = false;
    // The badge panel is normally driven with INVON; model its native polarity.
    this.inverted = true; this.commands = 0; this.ignored = new Set();
  }
  sample({ oled_scl: clock = 0, oled_sda: data = 0, oled_cs: cs = 1, oled_dc: dc = 0, oled_rst: rst = 1 }) {
    if (!rst) {
      if (!this.resetHeld) { this.reset(); this.resetHeld = true; }
      this.prevClock = clock; this.prevCs = cs; return;
    }
    this.resetHeld = false;
    if (cs) { this.bits = 0; this.byte = 0; }
    else if (!this.prevClock && clock) {
      this.byte = (this.byte << 1) | (data & 1);
      if (++this.bits === 8) { this.accept(this.byte & 255, dc); this.bits = 0; this.byte = 0; }
    }
    this.prevClock = clock; this.prevCs = cs;
  }
  accept(value, dc) {
    if (!dc) {
      this.command = value; this.args = []; this.high = null; this.commands++;
      switch (value) {
        case 0x01: this.reset(); break;
        case 0x10: this.sleep = true; break;
        case 0x11: this.sleep = false; break;
        case 0x28: this.displayOn = false; break;
        case 0x29: this.displayOn = true; break;
        case 0x20: case 0x21: {
          const next = value === 0x21;
          if (this.inverted !== next) for (let i=0;i<this.pixels.length;i++) if ((i&3)!==3) this.pixels[i]^=255;
          this.inverted = next; break;
        }
        case 0x2c: this.x = this.x0; this.y = this.y0; break;
        case 0x2a: case 0x2b: case 0x36: case 0x3a: case 0x3c: break;
        default: this.ignored.add(value);
      }
      return;
    }
    if (this.command === 0x2c || this.command === 0x3c) {
      if (this.colmod !== 5 && this.colmod !== 0x55) throw new Error(`GC9A01: unsupported pixel format 0x${this.colmod.toString(16)}; use RGB565.`);
      if (this.high === null) { this.high = value; return; }
      let x = this.x, y = this.y;
      if (this.madctl & 0x20) [x, y] = [y, x];
      if (this.madctl & 0x40) x = WIDTH - 1 - x;
      if (this.madctl & 0x80) y = HEIGHT - 1 - y;
      // Badge glass uses BGR native order; MADCTL BGR toggles that interpretation.
      this.put(y * WIDTH + x, (this.high << 8) | value, !(this.madctl & 8), !this.inverted);
      this.high = null;
      if (++this.x > this.x1) { this.x = this.x0; if (++this.y > this.y1) { this.y = this.y0; this.frames++; } }
      return;
    }
    this.args.push(value);
    if ((this.command === 0x2a || this.command === 0x2b) && this.args.length === 4) {
      const a = (this.args[0] << 8) | this.args[1], b = (this.args[2] << 8) | this.args[3];
      if (a > b || b > 239) throw new Error('GC9A01: invalid address window.');
      if (this.command === 0x2a) { this.x0 = a; this.x1 = b; } else { this.y0 = a; this.y1 = b; }
    } else if (this.command === 0x36) this.madctl = value;
    else if (this.command === 0x3a) this.colmod = value;
    // Ignore opaque vendor-command arguments until the next command byte.
    if (this.args.length > 8) this.args.shift();
  }
}
