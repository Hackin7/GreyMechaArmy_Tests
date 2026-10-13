#!/usr/bin/env python3
"""Compare mapped CPU read ports and prove bank decoding against 880cefb."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path


def run(args, output=None):
    subprocess.run(args, check=True, stdout=output)


def wrapper(entity, shared):
    accumulator = "ra when mul='1' else rs" if shared else 'ra'
    return f'''library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity registers is
 port(clk,reset,we,dest_user,mul,bl: in std_logic;
      mode,wmode: in std_logic_vector(3 downto 0);
      rn,rm,rd,ra,rs,wi: in unsigned(3 downto 0);
      wd,pc: in unsigned(31 downto 0);
      n,m,d,a: out unsigned(31 downto 0);
      s: out unsigned(7 downto 0));
end;
architecture rtl of registers is
 signal acc: unsigned(3 downto 0);
 signal adata: unsigned(31 downto 0);
begin
 acc <= to_unsigned(14,4) when bl='1' else {accumulator};
 {'s <= adata(7 downto 0);' if shared else ''}
 a <= adata;
 dut: entity work.{entity} port map(clk=>clk,reset=>reset,write_enable=>we,
 read_mode=>mode,write_mode=>wmode,write_index=>wi,write_data=>wd,pc=>pc,
 rn=>rn,rm=>rm,rd=>rd,ra=>acc,
 rs=>{'to_unsigned(0,4)' if shared else 'rs'},rb=>to_unsigned(0,4),
 block_user=>'0',dest_user=>dest_user,data_n=>n,data_m=>m,data_d=>d,
 data_a=>adata,data_s=>{'open' if shared else 's'},data_b=>open,data_lr=>open);
end;
'''


def address_module(source, name, optimized):
    # Test the actual VHDL functions, not a Python copy of their arithmetic.
    functions=source[source.index('  function '):source.index('\nbegin\n')]
    # Storage addresses are private. Map the new layout back to the original
    # one to prove that every architectural register retains its identity.
    translation='''
  function original_layout(address : integer) return integer is
  begin
    case address is
      when 14 => return 18; when 15 => return 19;
      when 16 => return 13; when 17 => return 14; when 18 => return 15;
      when 19 => return 16; when 20 => return 17;
      when 22 to 31 => return address-2;
      when others => return address;
    end case;
  end;
''' if optimized else ''
    call = 'original_layout(physical(idx,mode=x"1",stack_base(mode)))' if optimized else 'physical(idx,mode)'
    return f'''library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity {name} is port(idx: in unsigned(3 downto 0);
 mode: in std_logic_vector(3 downto 0); addr: out unsigned(4 downto 0)); end;
architecture rtl of {name} is
{functions}
{translation}
begin addr <= to_unsigned({call},5); end;
'''


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--work',type=Path,default=Path('/tmp/gba-cpu-register-area'))
    args=p.parse_args(); root=args.work.resolve(); root.mkdir(parents=True,exist_ok=True)
    old=Path('sim/gba_cpu_regfile_reference.vhd')
    new=Path('rtl/vhdl/gba_cpu_regfile.vhd')
    results={'inputs':{
        'reference_sha256':hashlib.sha256(old.read_bytes()).hexdigest(),
        'candidate_sha256':hashlib.sha256(new.read_bytes()).hexdigest(),
        'mapping_flags':'-noccu2 -nowidelut -no-rw-check',
        'scope':'isolated register-file and address-selection microbenchmark; not whole CPU or packed board'}}
    cases=[
        ('baseline',old,'gba_cpu_regfile_reference',False),
        ('shift-shared',old,'gba_cpu_regfile_reference',True),
        ('shift-shared-decode',new,'gba_cpu_regfile',True)]
    for label,source,entity,shared in cases:
        w=root/label; w.mkdir(exist_ok=True)
        top=w/'registers.vhd'; top.write_text(wrapper(entity,shared))
        run(['ghdl','-a','--std=08','--workdir='+str(w),str(source),str(top)])
        v=w/'registers.v'
        with v.open('w') as f:
            run(['ghdl','--synth','--std=08','--workdir='+str(w),'--out=verilog','registers'],f)
        v.write_text(v.read_text().replace('always @*','always_comb'))
        mapped=w/'mapped.json'
        with (w/'yosys.log').open('w') as f:
            run(['yosys','-Q','-T','-p',f'read_verilog -sv {v}; synth_ecp5 -top registers -noccu2 -nowidelut -no-rw-check; stat; write_json {mapped}'],f)
        cells=json.loads(mapped.read_text())['modules']['registers']['cells']
        counts={}
        for c in cells.values(): counts[c['type']]=counts.get(c['type'],0)+1
        results[label]=counts
        print(label,json.dumps(counts),flush=True)
    proof=root/'proof'; proof.mkdir(exist_ok=True)
    for source,name,optimized in [(old,'old_address',False),(new,'new_address',True)]:
        vh=proof/(name+'.vhd'); vh.write_text(address_module(source.read_text(),name,optimized))
        run(['ghdl','-a','--std=08','--workdir='+str(proof),str(vh)])
        with (proof/(name+'.v')).open('w') as f:
            run(['ghdl','--synth','--std=08','--workdir='+str(proof),'--out=verilog',name],f)
    miter=proof/'proof.v'
    miter.write_text('''module address_proof(input [3:0] idx,mode,output matches);
 wire [4:0] a,b; old_address old(idx,mode,a); new_address candidate(idx,mode,b);
 assign matches=a==b; endmodule\n''')
    with (proof/'yosys.log').open('w') as f:
        run(['yosys','-Q','-T','-p',f'read_verilog {proof}/old_address.v {proof}/new_address.v {miter}; prep -top address_proof -flatten; sat -verify -prove matches 1 -show-inputs'],f)
    results['address_equivalence']='PASS: all 16 mode encodings and 16 register indices, modulo private RAM layout'
    (root/'results.json').write_text(json.dumps(results,indent=2)+'\n')
    print(results['address_equivalence'])


if __name__=='__main__': main()
