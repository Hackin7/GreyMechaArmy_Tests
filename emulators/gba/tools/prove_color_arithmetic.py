#!/usr/bin/env python3
"""Prove shared color effects against equations extracted from upstream VHDL."""
from pathlib import Path
import re
import subprocess
from share_color_arithmetic import HELPER, share_color_arithmetic

if __name__ == '__main__':
    source = Path('vendor/openfpga-GBA/src/fpga/gba/gba_drawer_merge.vhd').read_text()
    output = Path('build/color-proof')
    output.mkdir(parents=True, exist_ok=True)
    (output/'gba_drawer_merge.vhd').write_text(share_color_arithmetic(source))
    expressions = []
    for mode in ('alpha', 'whiter', 'blacker'):
        matches = re.findall(r'^\s*' + mode + r'_blue\s*<=\s*(.*);$', source, re.M)
        assert len(matches) == 1
        expression = matches[0].replace('firstpixel_cycle3(14 downto 10)', 'first').replace('secondpixel(14 downto 10)', 'second')
        expressions.append(expression)
    original_function = '''
   function original_color(first, second : std_logic_vector(4 downto 0);
                           effect : unsigned(1 downto 0);
                           EVA_MAXED, EVB_MAXED, BLDY_MAXED : integer) return integer is
   begin
      case to_integer(effect) is
''' + '\n'.join(f'         when {index} => return {expression};' for index, expression in enumerate(expressions, 1)) + '''
         when others => return 0;
      end case;
   end function;
'''
    fixture = '''library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
entity color_proof is
   port(first, second : in std_logic_vector(4 downto 0);
        effect : in unsigned(1 downto 0);
        eva, evb, bldy : in unsigned(4 downto 0);
        equivalent : out std_logic);
end entity;
architecture proof of color_proof is
   function clamp(value : unsigned(4 downto 0)) return integer is
   begin
      if value < 16 then return to_integer(value); else return 16; end if;
   end function;
''' + HELPER + original_function + '''
begin
   equivalent <= '1' when original_color(first, second, effect, clamp(eva), clamp(evb), clamp(bldy)) =
                          shared_color(first, second, effect, clamp(eva), clamp(evb), clamp(bldy)) else '0';
end architecture;
'''
    (output/'color_proof.vhd').write_text(fixture)

    subprocess.run(['ghdl','-a','--std=08','--workdir='+str(output),str(output/'color_proof.vhd')],check=True)
    with (output/'color_proof.v').open('w') as verilog:
        subprocess.run(['ghdl','--synth','--std=08','--workdir='+str(output),'--out=verilog','color_proof'],stdout=verilog,check=True)
    subprocess.run(['yosys','-Q','-T','-p',
        f'read_verilog {output}/color_proof.v; prep -top color_proof -flatten; opt; '+
        '; '.join(f'sat -prove equivalent 1 -set effect {mode} -verify' for mode in range(4))],check=True)
    print('PASS shared color: all colors, effects, coefficients and coefficient saturation')
