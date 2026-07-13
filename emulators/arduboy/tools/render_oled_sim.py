#!/usr/bin/env python3
from pathlib import Path
import struct
import zlib


ROOT = Path(__file__).resolve().parents[1]
SIM = ROOT / "sim"


def write_ppm(path, width, height, pixels):
    with path.open("wb") as f:
        f.write(f"P6\n{width} {height}\n255\n".encode("ascii"))
        for r, g, b in pixels:
            f.write(bytes((r, g, b)))


def write_png(path, width, height, pixels):
    def chunk(kind, data):
        body = kind + data
        return (
            struct.pack(">I", len(data))
            + body
            + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
        )

    rows = []
    for y in range(height):
        row = bytearray([0])
        for r, g, b in pixels[y * width:(y + 1) * width]:
            row.extend((r, g, b))
        rows.append(bytes(row))

    raw = b"".join(rows)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def rgb565_to_rgb888(value):
    r = (value >> 11) & 0x1F
    g = (value >> 5) & 0x3F
    b = value & 0x1F
    return ((r * 255) // 31, (g * 255) // 63, (b * 255) // 31)


def render_fb(hex_path, ppm_path, png_path):
    data = [int(line.strip(), 16) for line in hex_path.read_text().splitlines() if line.strip()]
    if len(data) != 1024:
        raise ValueError(f"{hex_path} has {len(data)} bytes, expected 1024")

    pixels = []
    for y in range(64):
        page = y >> 3
        bit = y & 7
        for x in range(128):
            on = (data[page * 128 + x] >> bit) & 1
            pixels.append((255, 255, 255) if on else (0, 0, 0))
    write_ppm(ppm_path, 128, 64, pixels)
    write_png(png_path, 128, 64, pixels)


def render_panel(hex_path, ppm_path, png_path):
    data = [int(line.strip(), 16) for line in hex_path.read_text().splitlines() if line.strip()]
    if len(data) != 240 * 240:
        raise ValueError(f"{hex_path} has {len(data)} pixels, expected 57600")

    pixels = [rgb565_to_rgb888(value) for value in data]
    write_ppm(ppm_path, 240, 240, pixels)
    write_png(png_path, 240, 240, pixels)


def main():
    for mode in ("horizontal", "page"):
        render_fb(
            SIM / f"oled_decode_{mode}_fb.hex",
            SIM / f"oled_decode_{mode}_fb.ppm",
            SIM / f"oled_decode_{mode}_fb.png",
        )
        render_panel(
            SIM / f"oled_decode_{mode}_panel.hex",
            SIM / f"oled_decode_{mode}_panel.ppm",
            SIM / f"oled_decode_{mode}_panel.png",
        )
        print(f"wrote {mode} framebuffer and panel PPM/PNG images")


if __name__ == "__main__":
    main()
