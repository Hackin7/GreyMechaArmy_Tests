#!/usr/bin/env python3
import os


OUT_DIR = os.path.dirname(__file__)
HEX_PATH = os.path.join(OUT_DIR, "paddle_game.hex")
MEM_PATH = os.path.join(OUT_DIR, "paddle_game_words.mem")

IO_FB_ADDR_LO = 0x10
IO_FB_ADDR_HI = 0x11
IO_FB_DATA = 0x12
IO_BUZZER = 0x13
IO_BUTTONS = 0x15

BTN_LEFT = 3
BTN_RIGHT = 2


class Asm:
    def __init__(self):
        self.words = []
        self.labels = {}
        self.fixups = []
        self.rel_fixups = []

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
        assert 0 <= rd < 32
        self.emit(0x940A | (rd << 4))

    def brne(self, target_pc):
        offset = target_pc - self.pc()
        assert -64 <= offset <= 63
        self.emit(0xF401 | ((offset & 0x7F) << 3))

    def sbrs(self, rd, bit):
        assert 0 <= rd < 32
        assert 0 <= bit < 8
        self.emit(0xFE00 | ((rd & 0x10) << 4) | ((rd & 0x0F) << 4) | bit)

    def ijmp(self):
        self.emit(0x9409)

    def nop(self):
        self.emit(0x0000)

    def rel_jmp(self, label):
        self.rel_fixups.append((self.pc(), label))
        self.emit(0xC000)

    def abs_jmp(self, label):
        self.fixups.append((self.pc(), label))
        self.ldi(30, 0)
        self.ldi(30, 0)
        self.ldi(31, 0)
        self.ldi(31, 0)
        self.nop()
        self.nop()
        self.ijmp()

    def out_imm(self, addr, value, reg=16):
        self.ldi(reg, value)
        self.out(addr, reg)

    def resolve(self):
        for pc, label in self.rel_fixups:
            offset = self.labels[label] - pc
            assert -2048 <= offset <= 2047
            self.words[pc] = 0xC000 | (offset & 0x0FFF)
        for pc, label in self.fixups:
            target = self.labels[label]
            zl = target & 0xFF
            zh = (target >> 8) & 0xFF
            self.words[pc] = 0xE000 | ((zl & 0xF0) << 4) | ((30 - 16) << 4) | (zl & 0x0F)
            self.words[pc + 1] = 0xE000 | ((zl & 0xF0) << 4) | ((30 - 16) << 4) | (zl & 0x0F)
            self.words[pc + 2] = 0xE000 | ((zh & 0xF0) << 4) | ((31 - 16) << 4) | (zh & 0x0F)
            self.words[pc + 3] = 0xE000 | ((zh & 0xF0) << 4) | ((31 - 16) << 4) | (zh & 0x0F)


def set_pixel(fb, x, y):
    if 0 <= x < 128 and 0 <= y < 64:
        fb[(y // 8) * 128 + x] |= 1 << (y & 7)


def rect(fb, x0, y0, w, h):
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            set_pixel(fb, x, y)


def line_h(fb, x0, x1, y):
    for x in range(x0, x1 + 1):
        set_pixel(fb, x, y)


def line_v(fb, x, y0, y1):
    for y in range(y0, y1 + 1):
        set_pixel(fb, x, y)


def frame(ball_index, paddle_index):
    fb = bytearray(1024)
    line_h(fb, 0, 127, 0)
    line_h(fb, 0, 127, 63)
    line_v(fb, 0, 0, 63)
    line_v(fb, 127, 0, 63)

    for row in range(3):
        for col in range(10):
            if (row * 3 + col + ball_index) % 6 != 0:
                rect(fb, 14 + col * 10, 16 + row * 5, 8, 3)

    paddle_x = [24, 50, 76][paddle_index]
    rect(fb, paddle_x, 56, 28, 3)

    ball = [(30, 42), (92, 32)][ball_index]
    rect(fb, ball[0], ball[1], 4, 4)

    # Small motion ticks near the top make it obvious the AVR is cycling frames.
    for x in range(18, 112, 10):
        if ((x // 10) + ball_index) & 1:
            rect(fb, x, 6, 2, 2)
    return fb


def emit_frame(a, fb):
    a.out_imm(IO_FB_ADDR_LO, 0)
    a.out_imm(IO_FB_ADDR_HI, 0)
    for value in fb:
        a.out_imm(IO_FB_DATA, value)


def emit_delay(a, outer=90):
    a.out_imm(IO_BUZZER, 24)
    a.ldi(18, outer)
    outer_pc = a.pc()
    a.ldi(19, 255)
    inner_pc = a.pc()
    a.dec(19)
    a.brne(inner_pc)
    a.dec(18)
    a.brne(outer_pc)
    a.out_imm(IO_BUZZER, 0)


def emit_selector(a, prefix, next_label, ball_index):
    check_right = prefix + "_check_right"
    do_left = prefix + "_do_left"
    do_mid = prefix + "_do_mid"
    do_right = prefix + "_do_right"
    draw_left = prefix + "_left"
    draw_mid = prefix + "_mid"
    draw_right = prefix + "_right"

    a.in_(17, IO_BUTTONS)
    a.sbrs(17, BTN_LEFT)
    a.rel_jmp(check_right)
    a.rel_jmp(do_left)

    a.label(do_left)
    a.abs_jmp(draw_left)

    a.label(check_right)
    a.sbrs(17, BTN_RIGHT)
    a.rel_jmp(do_mid)
    a.rel_jmp(do_right)

    a.label(do_mid)
    a.abs_jmp(draw_mid)

    a.label(do_right)
    a.abs_jmp(draw_right)

    for label, paddle_index in ((draw_left, 0), (draw_mid, 1), (draw_right, 2)):
        a.label(label)
        emit_frame(a, frame(ball_index, paddle_index))
        emit_delay(a)
        a.abs_jmp(next_label)


def build_words():
    a = Asm()
    a.label("loop")
    emit_selector(a, "s0", "state1", 0)
    a.label("state1")
    emit_selector(a, "s1", "loop", 1)
    a.resolve()
    if len(a.words) > 16384:
        raise RuntimeError("program is %d words; max is 16384" % len(a.words))
    return a.words


def ihex_record(addr, rectype, data):
    total = len(data) + ((addr >> 8) & 0xFF) + (addr & 0xFF) + rectype + sum(data)
    checksum = (-total) & 0xFF
    return ":%02X%04X%02X%s%02X" % (
        len(data), addr, rectype, "".join("%02X" % b for b in data), checksum)


def write_hex(words):
    image = bytearray()
    for word in words:
        image.append(word & 0xFF)
        image.append((word >> 8) & 0xFF)
    lines = []
    for addr in range(0, len(image), 16):
        lines.append(ihex_record(addr, 0, image[addr:addr + 16]))
    lines.append(ihex_record(0, 1, b""))
    with open(HEX_PATH, "w", encoding="ascii") as f:
        f.write("\n".join(lines) + "\n")


def write_mem(words):
    with open(MEM_PATH, "w", encoding="ascii") as f:
        for word in words:
            f.write("%04x\n" % word)


def main():
    words = build_words()
    write_hex(words)
    write_mem(words)
    print("wrote %s" % HEX_PATH)
    print("wrote %s" % MEM_PATH)
    print("program words: %d" % len(words))


if __name__ == "__main__":
    main()
