#!/usr/bin/env python3
"""Map the isolated priority-memory variant; report capacity before routing."""
import argparse
import json
import re
import shutil
import subprocess
from collections import Counter
from pathlib import Path

p=argparse.ArgumentParser(description=__doc__);p.add_argument('--work',type=Path,default=Path('/tmp/greymecha_gba_bram_priority'));p.add_argument('--resume',action='store_true');p.add_argument('--carry',action='store_true');p.add_argument('--wide-luts',action='store_true',default=True);p.add_argument('--no-wide-luts',action='store_false',dest='wide_luts');p.add_argument('--output',type=Path,default=Path('build/bram-priority'));a=p.parse_args();w=a.work
shutil.copyfile('tools/ecp5_area.abc',w/'area.abc')
board=Path('board.mk').read_text()
rtl=re.search(r'^BOARD_RTL := (.*)$',board,re.M)[1]
for key,value in {'RAM_RTL':'../../io/fpga_psram_j1/src','GB_RTL':'../gameboy_gbc/rtl','OLED_RTL':'../arduboy/rtl/fast_oled'}.items():rtl=rtl.replace('$('+key+')',value)
sources=[]
for file in rtl.split():
    if file=='rtl/gba_core_wrapper.sv':file=str(w/'gba_core_wrapper_priority.sv')
    elif file in ['rtl/top.v','rtl/gba_host.v','rtl/gba_lines.v','rtl/gba_oled_init.v']:file=str(w/Path(file).name)
    sources.append(file)
sources += ['rtl/bram_priority/gba_local_mem.sv','rtl/bram_priority/gba_memory_fabric.sv','rtl/bram_priority/gba_scratch_arbiter.sv','rtl/bram_priority/gba_lines_psram.sv']
script=f'''read_verilog -I{w} -Irtl -I../arduboy/rtl/fast_oled -sv {w}/gba_top.v {' '.join(sources)};
chparam -set FLASH_QSPI 1 -set FLASH_CYCLES 2 -set FLASH_RX_REGISTER 0 -set PLL_CORE_DIV 26 -set PLL_FLASH_DIV 4 top;
scratchpad -set abc9.script {w}/area.abc;
synth_ecp5 -top top -noccu2 -nowidelut -no-rw-check -run begin:map_ram;
write_rtlil {w}/pre_ram.il;
synth_ecp5 -top top -noccu2 -nowidelut -run map_ram:map_gates;
write_rtlil {w}/pre_gates.il;
synth_ecp5 -top top -noccu2 -nowidelut -run map_gates:map_ffs;
dfflegalize -cell $_DFF_?_ 01 -cell $_DFF_?P?_ r -cell $_SDFF_?P?_ r -cell $_DFFE_??_ 01 -cell $_DFFE_?P??_ r -cell $_SDFFE_?P??_ r -cell $_DLATCH_?_ x -minsrst 2;
synth_ecp5 -top top -noccu2 -nowidelut -run map_ffs:check;
write_rtlil {w}/post_map.il;
hierarchy -check; check -assert; stat; write_rtlil {w}/mapped.il;
blackbox =A:whitebox; write_json {w}/top.json;
'''
flags=('' if a.carry else ' -noccu2')+('' if a.wide_luts else ' -nowidelut')
script=script.replace(' -noccu2 -nowidelut',flags)
(w/'map.ys').write_text(script)
if a.resume:
    script=f'read_rtlil {w}/pre_gates.il; read_verilog -lib -specify -overwrite +/ecp5/cells_sim.v +/ecp5/cells_bb.v; scratchpad -set abc9.script {w}/area.abc;'+script.split(f'write_rtlil {w}/pre_gates.il;')[1]
    (w/'resume.ys').write_text(script)
log=a.output;log.mkdir(parents=True,exist_ok=True)
with (log/'yosys.log').open('w') as f:subprocess.run(['yosys','-Q','-T','-s',str(w/('resume.ys' if a.resume else 'map.ys'))],stdout=f,stderr=subprocess.STDOUT,check=True)
cells=json.loads((w/'top.json').read_text())['modules']['top']['cells'];counts=Counter(c['type'] for c in cells.values())
with (log/'pack.log').open('w') as f:
    subprocess.run(['nextpnr-ecp5','--25k','--package','CABGA256','--speed','6','--json',str(w/'top.json'),'--lpf','pinout.lpf','--pack-only'],stdout=f,stderr=subprocess.STDOUT,check=True)
pack=(log/'pack.log').read_text()
sites=int(re.search(r'TRELLIS_COMB:\s*(\d+)',pack)[1])
pll=next(c['parameters'] for n,c in cells.items() if c['type']=='EHXPLLL' and 'quad_clock' in n)
div=lambda name:int(pll[name],2)
sck=(310/6)*div('CLKFB_DIV')/div('CLKI_DIV')*div('CLKOP_DIV')/div('CLKOS2_DIV')/2
report={'cells':dict(counts),'packed_logic_sites':sites,'logic_capacity':24288,
        'routing_allowed':sites<=24288 and counts['DP16KD']<=56 and counts['MULT18X18D']<=28,
        'memory_layout':{'BIOS':16384,'IWRAM':32768,'lower_VRAM':65536},'nominal_qspi_sck_mhz':sck,'maximum_qspi_sck_mhz':sck*1.15,'timing_validated':False,'carry_mapping':a.carry,'wide_lut_mapping':a.wide_luts}
(log/'resources.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
