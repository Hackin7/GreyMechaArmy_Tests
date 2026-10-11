#!/usr/bin/env python3
"""Exhaustively prove ADD/ADC/SUB/SBC values and ARM carry/borrow flags."""
from pathlib import Path
import subprocess
from share_cpu_arithmetic import share_cpu_arithmetic

folder = Path('build/cpu-proof')
folder.mkdir(parents=True, exist_ok=True)
share_cpu_arithmetic(Path('vendor/openfpga-GBA/src/fpga/gba/gba_cpu.vhd').read_text())
source = 'rtl/vhdl/gba_alu_addsub.vhd'
subprocess.run(['ghdl','-a','--std=08','--workdir='+str(folder),source],check=True)
verilog=folder/'gba_alu_addsub.v'
with verilog.open('w') as output:
    subprocess.run(['ghdl','--synth','--std=08','--workdir='+str(folder),'--out=verilog','gba_alu_addsub'],stdout=output,check=True)
subprocess.run(['yosys','-Q','-T','-p',f'read_verilog {verilog} sim/cpu_arithmetic_proof.v; prep -top cpu_arithmetic_proof -flatten; sat -verify -prove matches 1 -show-inputs'],check=True)
print('PASS shared CPU arithmetic: all operands and carry inputs for ADD/ADC/SUB/SBC, including carry/borrow')
