#!/usr/bin/env python3
"""Compare ECP5 LUT mapping from a saved pre_gates.il checkpoint."""
import argparse
import subprocess
from pathlib import Path


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('checkpoint',type=Path)
    p.add_argument('--work',type=Path,required=True)
    p.add_argument('--wide-luts',action='store_true')
    p.add_argument('--from-ram',action='store_true',help='resume pre_ram.il before RAM mapping')
    args=p.parse_args(); w=args.work.resolve(); w.mkdir(parents=True,exist_ok=True)
    abc=w/'area.abc'; abc.write_text(Path('tools/ecp5_area.abc').read_text())
    flags='-noccu2' + ('' if args.wide_luts else ' -nowidelut')
    ram_mapping=f'synth_ecp5 -top top {flags} -run map_ram:map_gates; write_rtlil {w}/pre_gates.il;' if args.from_ram else ''
    commands=f'''read_rtlil {args.checkpoint.resolve()};
read_verilog -lib -specify -overwrite +/ecp5/cells_sim.v +/ecp5/cells_bb.v;
scratchpad -set abc9.script {abc};
{ram_mapping}
synth_ecp5 -top top {flags} -run map_gates:map_ffs;
dfflegalize -cell $_DFF_?_ 01 -cell $_DFF_?P?_ r -cell $_SDFF_?P?_ r -cell $_DFFE_??_ 01 -cell $_DFFE_?P??_ r -cell $_SDFFE_?P??_ r -cell $_DLATCH_?_ x -minsrst 2;
synth_ecp5 -top top {flags} -run map_ffs:check;
hierarchy -check; check -assert; stat;
blackbox =A:whitebox; write_json {w}/top.json'''
    with (w/'yosys.log').open('w') as log:
        subprocess.run(['yosys','-Q','-T','-p',commands],stdout=log,stderr=log,check=True)
    print(w/'top.json')


if __name__=='__main__': main()
