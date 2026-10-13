#!/usr/bin/env python3
"""Run the same loader/CPU/PPU checks against direct and packed local RAM."""
import subprocess
from pathlib import Path
w=Path('build/bram-priority-tests');w.mkdir(parents=True,exist_ok=True)
for packed in (False,True):
    source=Path('sim/tb_gba_local_mem.sv').read_text()
    if packed:source=source.replace('gba_local_mem dut','gba_local_mem_packed dut')
    name='packed' if packed else 'direct'
    fixture=w/('tb_'+name+'.sv');fixture.write_text(source)
    exe=w/(name+'.vvp')
    subprocess.run(['iverilog','-g2012','-s','tb_gba_local_mem','-o',str(exe),'rtl/bram_priority/gba_local_mem.sv','rtl/bram_priority/gba_local_mem_packed.sv',str(fixture)],check=True)
    subprocess.run(['vvp',str(exe)],check=True)
subprocess.run(['ghdl','-a','--std=08','--workdir='+str(w),'rtl/bram_priority/gba_vram_hi_external.vhd','sim/tb_gba_vram_hi_external.vhd'],check=True)
subprocess.run(['ghdl','-r','--std=08','--workdir='+str(w),'tb_gba_vram_hi_external','--assert-level=error'],check=True)
