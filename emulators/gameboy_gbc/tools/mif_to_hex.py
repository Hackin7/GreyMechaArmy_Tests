#!/usr/bin/env python3
"""Convert the byte-oriented MiSTer boot-ROM MIF into readmemh format."""

import argparse
import re
from pathlib import Path


LINE_RE = re.compile(r"^\s*([0-9A-Fa-f]+)\s*:\s*(.*?)\s*;\s*$")


def convert(source: Path, destination: Path) -> None:
    memory = bytearray(4096)
    seen = set()

    for raw_line in source.read_text(encoding="ascii").splitlines():
        line = raw_line.split("--", 1)[0]
        match = LINE_RE.match(line)
        if not match:
            continue

        address = int(match.group(1), 16)
        values = [int(token, 16) for token in match.group(2).split()]
        for offset, value in enumerate(values):
            index = address + offset
            if index >= len(memory):
                raise ValueError(f"MIF address 0x{index:x} exceeds 4 KiB boot ROM")
            memory[index] = value
            seen.add(index)

    if len(seen) != len(memory):
        missing = len(memory) - len(seen)
        raise ValueError(f"MIF did not initialize {missing} byte(s)")

    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("".join(f"{value:02x}\n" for value in memory), encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    convert(args.source, args.destination)


if __name__ == "__main__":
    main()
