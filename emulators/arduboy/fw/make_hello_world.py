#!/usr/bin/env python3
from pathlib import Path


OUT_DIR = Path(__file__).resolve().parent
HEX_PATH = OUT_DIR / "hello_world.hex"
MEM_PATH = OUT_DIR / "hello_world_words.mem"

DDRD = 0x0A
PORTD = 0x0B
SPCR = 0x2C
SPSR = 0x2D
SPDR = 0x2E

PD_DC = 1 << 4
PD_CS = 1 << 6
PD_RST = 1 << 7


class Asm:
    def __init__(self):
        self.words = []
        self.labels = {}
        self.fixups = []

    def pc(self):
        return len(self.words)

    def label(self, name):
        self.labels[name] = self.pc()

    def emit(self, word):
        self.words.append(word & 0xFFFF)

    def ldi(self, rd, value):
        assert 16 <= rd <= 31
        value &= 0xFF
        self.emit(0xE000 | ((value & 0xF0) << 4) | ((rd - 16) << 4) | (value & 0x0F))

    def out(self, addr, rr):
        assert 0 <= addr < 64
        assert 0 <= rr < 32
        self.emit(0xB800 | ((addr & 0x30) << 5) | (rr << 4) | (addr & 0x0F))

    def in_(self, rd, addr):
        assert 0 <= addr < 64
        assert 0 <= rd < 32
        self.emit(0xB000 | ((addr & 0x30) << 5) | (rd << 4) | (addr & 0x0F))

    def dec(self, rd):
        self.emit(0x940A | (rd << 4))

    def brne(self, label):
        self.fixups.append((self.pc(), label, "brne"))
        self.emit(0xF401)

    def rjmp(self, label):
        self.fixups.append((self.pc(), label, "rjmp"))
        self.emit(0xC000)

    def sbrs(self, rd, bit):
        self.emit(0xFE00 | ((rd & 0x10) << 4) | ((rd & 0x0F) << 4) | bit)

    def out_imm(self, addr, value, reg=16):
        self.ldi(reg, value)
        self.out(addr, reg)

    def resolve(self):
        for pc, label, kind in self.fixups:
            offset = self.labels[label] - (pc + 1)
            if kind == "rjmp":
                assert -2048 <= offset <= 2047
                self.words[pc] = 0xC000 | (offset & 0x0FFF)
            else:
                assert -64 <= offset <= 63
                self.words[pc] = 0xF401 | ((offset & 0x7F) << 3)


def delay(a, label_prefix, outer=24):
    a.ldi(18, outer)
    a.label(label_prefix + "_outer")
    a.ldi(19, 255)
    a.label(label_prefix + "_inner")
    a.dec(19)
    a.brne(label_prefix + "_inner")
    a.dec(18)
    a.brne(label_prefix + "_outer")


def spi_send(a, value, label_prefix):
    a.out_imm(SPDR, value)
    a.label(label_prefix)
    a.in_(17, SPSR)
    a.sbrs(17, 7)
    a.rjmp(label_prefix)


def font_columns(text):
    font = {
        " ": [0x00, 0x00, 0x00, 0x00, 0x00],
        "!": [0x00, 0x00, 0x5F, 0x00, 0x00],
        "D": [0x7F, 0x41, 0x41, 0x22, 0x1C],
        "E": [0x7F, 0x49, 0x49, 0x49, 0x41],
        "H": [0x7F, 0x08, 0x08, 0x08, 0x7F],
        "L": [0x7F, 0x40, 0x40, 0x40, 0x40],
        "O": [0x3E, 0x41, 0x41, 0x41, 0x3E],
        "R": [0x7F, 0x09, 0x19, 0x29, 0x46],
        "W": [0x7F, 0x20, 0x18, 0x20, 0x7F],
    }
    out = []
    for ch in text:
        out.extend(font[ch])
        out.append(0x00)
    return out


def build_frame():
    fb = bytearray(1024)
    text = font_columns("HELLO WORLD!")
    start = (128 - len(text)) // 2
    page = 3
    for i, col in enumerate(text):
        fb[page * 128 + start + i] = col
    for x in range(128):
        fb[x] = 0x01
        fb[7 * 128 + x] = 0x80
    for page in range(8):
        fb[page * 128] = 0xFF
        fb[page * 128 + 127] = 0xFF
    return fb


def build_words():
    a = Asm()
    a.out_imm(DDRD, PD_DC | PD_CS | PD_RST)
    a.out_imm(PORTD, PD_CS | PD_RST)
    a.out_imm(SPCR, 0x50)

    a.out_imm(PORTD, PD_CS)
    delay(a, "rst_low", 20)
    a.out_imm(PORTD, PD_CS | PD_RST)
    delay(a, "rst_high", 20)

    a.out_imm(PORTD, PD_RST)
    commands = [
        0xAE, 0xD5, 0x80, 0xA8, 0x3F, 0xD3, 0x00, 0x40,
        0x8D, 0x14, 0x20, 0x00, 0x21, 0x00, 0x7F, 0x22,
        0x00, 0x07, 0xA1, 0xC8, 0xDA, 0x12, 0x81, 0xCF,
        0xD9, 0xF1, 0xDB, 0x40, 0xA4, 0xA6, 0xAF,
    ]
    for i, value in enumerate(commands):
        spi_send(a, value, "cmd_%03d" % i)

    a.out_imm(PORTD, PD_RST | PD_DC)
    for i, value in enumerate(build_frame()):
        spi_send(a, value, "data_%04d" % i)

    a.label("idle")
    a.rjmp("idle")
    a.resolve()
    if len(a.words) > 16384:
        raise RuntimeError("program is %d words; max is 16384" % len(a.words))
    return a.words


def ihex_record(addr, rectype, data):
    total = len(data) + ((addr >> 8) & 0xFF) + (addr & 0xFF) + rectype + sum(data)
    checksum = (-total) & 0xFF
    return ":%02X%04X%02X%s%02X" % (
        len(data), addr, rectype, "".join("%02X" % b for b in data), checksum)


def write_outputs(words):
    image = bytearray()
    for word in words:
        image.append(word & 0xFF)
        image.append((word >> 8) & 0xFF)
    lines = [ihex_record(addr, 0, image[addr:addr + 16]) for addr in range(0, len(image), 16)]
    lines.append(ihex_record(0, 1, b""))
    HEX_PATH.write_text("\n".join(lines) + "\n", encoding="ascii")
    MEM_PATH.write_text("".join("%04x\n" % word for word in words), encoding="ascii")


def main():
    words = build_words()
    write_outputs(words)
    print("wrote %s" % HEX_PATH)
    print("wrote %s" % MEM_PATH)
    print("program words: %d" % len(words))


if __name__ == "__main__":
    main()
