#!/usr/bin/env python3
"""Preserve RAM initialization using readmemh rather than huge init processes.

GHDL expands zero-filled arrays into thousands of assignment statements.
Yosys's PROC pass is slow on these. readmemh gives the same power-up contents
directly to the memory frontend. Scalar initialization is unchanged.
"""
import argparse
import re
from pathlib import Path


def compact(source, folder, board_memory=False):
    replaced = 0
    pattern = r"initial\s+begin\s+((?:\w+\[\d+\]\s*=\s*\d+'b[01]+;\s*)+)end"

    def lower(match):
        nonlocal replaced
        assignments = re.findall(r"(\w+)\[(\d+)\]\s*=\s*(\d+)'b([01]+)", match[1])
        names = {a[0] for a in assignments}
        widths = {int(a[2]) for a in assignments}
        if len(names) != 1 or len(widths) != 1 or any(int(a[3], 2) for a in assignments):
            return match[0]
        length = len(assignments)
        if sorted(int(a[1]) for a in assignments) != list(range(length)):
            return match[0]
        width = widths.pop()
        file = folder / ('zero_%d_%d.hex' % (width, length))
        file.write_text(('0' * ((width + 3) // 4) + '\n') * length)
        replaced += 1
        return 'initial $readmemh("%s", %s);' % (file.as_posix(), names.pop())

    result = re.sub(pattern, lower, source)
    # SystemVerilog always_comb also executes constant-only combinational
    # processes once at startup, unlike GHDL's emitted always @*.
    result = result.replace('always @*', 'always_comb')
    if board_memory:
        # External low VRAM frees EBRs for the cartridge data/tag cache, OAM
        # and palettes. Avoid spending thousands of logic sites on LUT RAM.
        modules = ('syncramdual_Brtl_Lmem_64_6', 'syncramdual_Brtl_Lmem_18_6',
                   'syncramdual_Brtl_Lmem_3_8',
                   'syncramdualnotpow2_Brtl_Lmem_8_256',
                   'syncramdualnotpow2_Brtl_Lmem_8_128')
        for module in modules:
            pattern = r'(module ' + module + r'\b.*?)(reg \[[^\n]+\] ram\[[^\n]+)'
            result, count = re.subn(pattern, r'\1(* ram_style = "block" *) \2', result, flags=re.S)
            if count != 1:
                raise ValueError('Expected one RAM declaration in ' + module)
        # Sprite metadata now clears one entry per cycle between scanlines.
        # GHDL splits its priority and coverage write enables into two arrays.
        result, count = re.subn(r'(?m)^(  reg (?:\[[^\n]+?\] )?pixelarray_n\d+\[[^\n]+)',
                               r'  (* ram_style = "block" *) \1', result)
        if count != 2:
            raise ValueError('Expected two sprite metadata RAM declarations')
        # Optional object-window RAM uses the same registered read latency.
        result = re.sub(r'(?m)^(  reg linebuffer_objwindow\[\d+:\d+\][^\n]*)',
                        r'  (* ram_style = "block" *) \1', result)
    print('Compacted %d zero-initialized RAMs' % replaced)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('file', type=Path)
    parser.add_argument('--board-memory', action='store_true')
    args = parser.parse_args()
    file = args.file.resolve()
    file.write_text(compact(file.read_text(), file.parent, args.board_memory))
