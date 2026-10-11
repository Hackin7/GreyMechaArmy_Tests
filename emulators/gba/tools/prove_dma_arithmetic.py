#!/usr/bin/env python3
"""Exhaustively prove shared DMA stepping against the upstream VHDL block."""
from pathlib import Path
import subprocess
from share_dma_arithmetic import DECLARATIONS, COMBINATIONAL, SOURCE_ENABLE, TARGET_ENABLE, share_dma_arithmetic

folder = Path('build/dma-proof')
folder.mkdir(parents=True, exist_ok=True)
original = Path('vendor/openfpga-GBA/src/fpga/gba/gba_dma_module.vhd').read_text()
share_dma_arithmetic(original)  # Reject a changed upstream update template.
start = original.index("                           if (Transfer_Type_DW = '1') then", original.index('addr_source <= addr_source + 4') - 300)
end = original.index('\n                           -- timing', start)
oracle = original[start:end].replace('addr_source <=', 'source_ref <=').replace('addr_target <=', 'target_ref <=')
probe = '''library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity dma_address_proof is port(
  addr_source, addr_target : in unsigned(27 downto 0);
  Transfer_Type_DW : in std_logic;
  source_Adr_Control, dest_Addr_Control, Start_Timing : in integer range 0 to 3;
  matches : out std_logic);
end;
architecture rtl of dma_address_proof is
  signal source_ref,target_ref,source_shared,target_shared : unsigned(27 downto 0);
''' + DECLARATIONS + '\nbegin\n' + COMBINATIONAL + f'''
  source_shared <= next_source when ({SOURCE_ENABLE}) else addr_source;
  target_shared <= next_target when ({TARGET_ENABLE}) else addr_target;
  process(all) begin
    source_ref <= addr_source; target_ref <= addr_target;
''' + oracle + '''
  end process;
  matches <= '1' when source_ref=source_shared and target_ref=target_shared else '0';
end;
'''
source = folder / 'dma_address_proof.vhd'
source.write_text(probe)
subprocess.run(['ghdl', '-a', '--std=08', '--workdir=' + str(folder), str(source)], check=True)
verilog = folder / 'dma_address_proof.v'
with verilog.open('w') as output:
    subprocess.run(['ghdl', '--synth', '--std=08', '--workdir=' + str(folder), '--out=verilog', 'dma_address_proof'], stdout=output, check=True)
subprocess.run(['yosys', '-Q', '-T', '-p',
    f'read_verilog {verilog}; prep -top dma_address_proof -flatten; sat -verify -prove matches 1 -show-inputs'], check=True)
print('PASS shared DMA arithmetic: all addresses, widths, increment/decrement/fixed/reload modes, start timings and cartridge overrides')
