#!/usr/bin/env python3
"""Make GHDL's synthesized GBse Verilog acceptable to SystemVerilog tools.

GHDL emits the VHDL port name ``do`` verbatim, but ``do`` is a SystemVerilog
keyword.  It also emits one duplicate ``alu_q`` net declaration which Yosys
accepts and Icarus correctly rejects.  This creates a simulation-only copy;
the synthesis input remains untouched.
"""

import argparse
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()

    text = args.source.read_text(encoding="utf-8")
    # GHDL releases differ: older versions emit the illegal SystemVerilog
    # identifier ``do`` verbatim, while newer versions escape it as ``\do ``.
    variants = (
        (
            ("output [7:0] do,", "output [7:0] dout,"),
            ("assign do =", "assign dout ="),
            (".do(u0_do)", ".dout(u0_do)"),
        ),
        (
            ("output [7:0] \\do ,", "output [7:0] dout,"),
            ("assign \\do  =", "assign dout ="),
            (".\\do (n9417)", ".dout(n9417)"),
        ),
    )
    selected = next(
        (group for group in variants if all(text.count(old) == 1 for old, _ in group)),
        None,
    )
    if selected is None:
        raise SystemExit("could not identify GHDL's generated T80 `do` port form")
    for old, new in selected:
        text = text.replace(old, new)

    duplicate = "  wire [7:0] alu_q;\n"
    duplicate_count = text.count(duplicate)
    if duplicate_count == 2:
        text = text.replace(duplicate, "", 1)
    elif duplicate_count != 1:
        raise SystemExit(
            f"expected one or two generated alu_q declarations, found {duplicate_count}"
        )

    args.destination.parent.mkdir(parents=True, exist_ok=True)
    args.destination.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
