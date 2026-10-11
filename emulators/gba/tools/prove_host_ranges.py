#!/usr/bin/env python3
"""Prove narrowed host arithmetic against the last committed host RTL."""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[3]
original = subprocess.run(
    ['git', '-c', 'safe.directory=' + str(root), 'show',
     '75f37e5:emulators/gba/rtl/gba_host.v'],
    check=True, capture_output=True, text=True).stdout
current = Path('rtl/gba_host.v').read_text()


def condition(source, pattern):
    found = re.findall(pattern, source)
    assert len(found) == 1
    return found[0]


patterns = {
    'write': r"8'h10: if\((.*?)\) begin",
    'fill': r"8'h14: if\((.*?)\) begin",
    'read_bad': r"if\(opcode==8'h12&&\((.*?)\)\) begin exec_state<=0;error<=5;end",
    'save_bad': r"if\(opcode==8'h15&&\((.*?)\)\) begin exec_state<=0;error<=5;end",
}
probe = '''module host_ranges(input [31:0] address, fill,
  input [8:0] length, input run, pause,
  input [23:0] remaining, input save_step, output matches);
  wire [7:0] params[0:4];
  assign params[0]=fill[7:0]; assign params[1]=fill[15:8];
  assign params[2]=fill[23:16]; assign params[3]=fill[31:24];
  assign params[4]=0;
  wire read_valid=fill[15:0]>0 && fill[15:0]<=256;
  wire [23:0] step=save_step ? 24'd1 : 24'd4;
  wire [23:0] narrowed_next=remaining-step;
  wire [31:0] original_next={8'd0,remaining}-{8'd0,step};
  wire counter_matches=remaining<step || remaining>24'h800000 ||
                       {8'd0,narrowed_next}==original_next;
'''
for name, pattern in patterns.items():
    for label, source in [('old', original), ('new', current)]:
        probe += f'  wire {name}_{label}=({condition(source, pattern)});\n'
probe += '''  assign matches=write_old==write_new && fill_old==fill_new &&
    (!read_valid || (read_bad_old==read_bad_new && save_bad_old==save_bad_new)) &&
    counter_matches;
endmodule
'''
folder = Path('build/host-range-proof')
folder.mkdir(parents=True, exist_ok=True)
source = folder / 'host_ranges.v'
source.write_text(probe)
subprocess.run(['yosys', '-Q', '-T', '-p',
    f'read_verilog {source}; prep -top host_ranges -flatten; '
    'sat -verify -prove matches 1 -show-inputs'], check=True)
print('PASS host ranges: all addresses, lengths, fill sizes, read/save bounds and legal counter steps')
