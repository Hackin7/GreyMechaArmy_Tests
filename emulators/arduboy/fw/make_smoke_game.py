#!/usr/bin/env python3
import os


OUT_DIR = os.path.dirname(__file__)
HEX_PATH = os.path.join(OUT_DIR, "smoke_game.hex")
MEM_PATH = os.path.join(OUT_DIR, "smoke_game_words.mem")

IO_FB_ADDR_LO = 0x10
IO_FB_ADDR_HI = 0x11
IO_FB_DATA = 0x12
IO_BUZZER = 0x13


def op_ldi(rd, value):
    assert 16 <= rd <= 31
    value &= 0xFF
    return 0xE000 | ((value & 0xF0) << 4) | ((rd - 16) << 4) | (value & 0x0F)


def op_out(addr, rr):
    assert 0 <= addr < 64
    assert 0 <= rr < 32
    return 0xB800 | ((addr & 0x30) << 5) | (rr << 4) | (addr & 0x0F)


def op_dec(rd):
    assert 0 <= rd < 32
    return 0x940A | (rd << 4)


def op_brne(offset):
    assert -64 <= offset <= 63
    return 0xF401 | ((offset & 0x7F) << 3)


def op_rjmp(offset):
    assert -2048 <= offset <= 2047
    return 0xC000 | (offset & 0x0FFF)


def op_ijmp():
    return 0x9409


def emit_out_imm(words, addr, value, reg=16):
    words.append(op_ldi(reg, value))
    words.append(op_out(addr, reg))


def emit_delay(words, outer=220):
    emit_out_imm(words, IO_BUZZER, 36)
    words.append(op_ldi(18, outer))
    outer_pc = len(words)
    words.append(op_ldi(19, 255))
    inner_pc = len(words)
    words.append(op_dec(19))
    words.append(op_brne(inner_pc - len(words)))
    words.append(op_dec(18))
    words.append(op_brne(outer_pc - len(words)))
    emit_out_imm(words, IO_BUZZER, 0)


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


def frame(index):
    fb = bytearray(1024)
    line_h(fb, 0, 127, 0)
    line_h(fb, 0, 127, 63)
    line_v(fb, 0, 0, 63)
    line_v(fb, 127, 0, 63)
    line_h(fb, 8, 119, 12)
    line_h(fb, 8, 119, 51)
    line_v(fb, 8, 12, 51)
    line_v(fb, 119, 12, 51)

    # A tiny "Breakout-ish" scene: bricks, paddle, ball, and moving sweep.
    for row in range(3):
        for col in range(10):
            if (row + col + index) % 5 != 0:
                rect(fb, 14 + col * 10, 17 + row * 5, 8, 3)

    paddle_x = 46 + ((index * 9) % 28)
    rect(fb, paddle_x, 56, 28, 3)

    bx = 20 + index * 14
    by = [45, 39, 33, 27, 31, 37, 43][index]
    rect(fb, bx, by, 4, 4)

    for x in range(18, 111, 8):
        if ((x // 8) + index) & 1:
            set_pixel(fb, x, 6)
            set_pixel(fb, x + 1, 6)
    return fb


def build_words():
    words = []
    for i in range(7):
        emit_out_imm(words, IO_FB_ADDR_LO, 0)
        emit_out_imm(words, IO_FB_ADDR_HI, 0)
        for value in frame(i):
            emit_out_imm(words, IO_FB_DATA, value)
        emit_delay(words)
    words.append(op_ldi(30, 0))
    words.append(op_ldi(31, 0))
    words.append(op_ijmp())
    if len(words) > 16384:
        raise RuntimeError("program is %d words; max is 16384" % len(words))
    return words


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
