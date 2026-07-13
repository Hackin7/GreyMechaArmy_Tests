#!/usr/bin/env python3
import argparse


def parse_ihex(path, size):
    image = bytearray([0xFF] * size)
    upper = 0
    high = 0
    with open(path, "r", encoding="ascii") as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            if not line.startswith(":"):
                raise ValueError("%s:%d: missing ':'" % (path, lineno))
            count = int(line[1:3], 16)
            addr = int(line[3:7], 16)
            rectype = int(line[7:9], 16)
            payload = bytes(int(line[9 + i * 2:11 + i * 2], 16) for i in range(count))
            checksum = int(line[9 + count * 2:11 + count * 2], 16)
            total = count + (addr >> 8) + (addr & 0xFF) + rectype + sum(payload) + checksum
            if total & 0xFF:
                raise ValueError("%s:%d: bad checksum" % (path, lineno))
            if rectype == 0x00:
                base = upper + addr
                for i, value in enumerate(payload):
                    if 0 <= base + i < size:
                        image[base + i] = value
                        high = max(high, base + i + 1)
            elif rectype == 0x01:
                break
            elif rectype == 0x04:
                upper = int.from_bytes(payload, "big") << 16
    return image, high


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input_hex")
    parser.add_argument("output_mem")
    parser.add_argument("--size", type=lambda x: int(x, 0), default=32768)
    args = parser.parse_args()

    image, high = parse_ihex(args.input_hex, args.size)
    with open(args.output_mem, "w", encoding="ascii") as f:
        for i in range(0, len(image), 2):
            f.write("%02x%02x\n" % (image[i + 1], image[i]))
    print("wrote %s (%d used bytes, %d words)" % (args.output_mem, high, len(image) // 2))


if __name__ == "__main__":
    main()
