#!/usr/bin/env python3
"""Prove the shared ARM shift network against the independent shifters."""
from pathlib import Path
import subprocess

folder=Path('build/shifter-proof')
folder.mkdir(parents=True,exist_ok=True)
subprocess.run(['ghdl','-a','--std=08','--workdir='+str(folder),
                'rtl/vhdl/gba_alu_shifter.vhd'],check=True)
verilog=folder/'gba_alu_shifter.v'
with verilog.open('w') as output:
    subprocess.run(['ghdl','--synth','--std=08','--workdir='+str(folder),
                    '--out=verilog','gba_alu_shifter'],stdout=output,check=True)
verilog.write_text(verilog.read_text().replace('always @*','always_comb'))
subprocess.run(['yosys','-Q','-T','-p',
    f'read_verilog -sv {verilog} sim/cpu_shifter_proof.v; '
    'prep -top cpu_shifter_proof -flatten; '
    'sat -verify -prove matches 1 -show-inputs'],check=True)
print('PASS shared CPU shifter: all values, 256 amounts, four modes, RRX and carry inputs')
