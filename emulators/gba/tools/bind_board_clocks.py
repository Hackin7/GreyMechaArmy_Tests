#!/usr/bin/env python3
"""Give the board PLL output bits unique names before applying the LPF.

Yosys can discard top-level wire names while retaining hierarchical aliases.
Connections in JSON use bit IDs, so removing aliases changes no logic. Unique
names avoid depending on nextpnr's choice among equivalent aliases.
"""
import argparse
import json
from pathlib import Path
import re


def bind(netlist, frequencies):
    top=netlist['modules']['top']
    cells=top['cells']
    def output(cell,port):
        if cell not in cells or cells[cell]['type']!='EHXPLLL':
            raise ValueError(f'missing expected PLL: {cell}')
        bits=cells[cell]['connections'][port]
        if len(bits)!=1 or not isinstance(bits[0],int):
            raise ValueError(f'invalid PLL output: {cell}.{port}')
        return bits[0]
    main='clocks.pll'
    quad='quad_clock.clocks.pll'
    roles={
        'clk_core':output(main,'CLKOP'),
        'clk_panel':output(main,'CLKOS'),
        'clk_ram':output(main,'CLKOS2'),
        'clk_flash':output(quad,'CLKOS2') if quad in cells else output(main,'CLKOS2'),
    }
    if len({roles[k] for k in ('clk_core','clk_panel','clk_ram')})!=3:
        raise ValueError('unexpected primary PLL topology')
    nets=top['netnames']
    bindings=[]
    # SPI fallback can share RAM/flash clock bits; constrain that net once,
    # using the larger requirement, rather than silently overriding a target.
    for bit in dict.fromkeys(roles.values()):
        names=[role for role,value in roles.items() if value==bit]
        name=names[0]
        if name in nets and nets[name]['bits']!=[bit]:
            raise ValueError(f'clock name already belongs to another net: {name}')
        aliases=[alias for alias,value in nets.items() if value['bits']==[bit]]
        if not aliases:
            raise ValueError(f'missing aliases for {name}')
        for port,value in top.get('ports',{}).items():
            if bit in value['bits']:
                raise ValueError(f'board clock unexpectedly drives IO port {port}')
        attributes=dict(nets[name if name in aliases else aliases[0]].get('attributes',{}))
        for alias in aliases:del nets[alias]
        nets[name]={'hide_name':0,'bits':[bit],'attributes':attributes}
        bindings.append({'name':name,'roles':names,'mhz':max(frequencies[role] for role in names)})
    return bindings


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('netlist',type=Path)
    p.add_argument('pins',type=Path)
    p.add_argument('--output-json',type=Path,required=True)
    p.add_argument('--output-lpf',type=Path,required=True)
    p.add_argument('--manifest',type=Path,required=True)
    for role in ('core','panel','ram','flash'):
        p.add_argument('--'+role,type=float,required=True)
    a=p.parse_args()
    frequencies={'clk_'+role:getattr(a,role) for role in ('core','panel','ram','flash')}
    if any(value<=0 for value in frequencies.values()):p.error('clock targets must be positive')
    netlist=json.loads(a.netlist.read_text())
    bindings=bind(netlist,frequencies)
    pins=a.pins.read_text()
    for role in frequencies:
        pins,count=re.subn(rf'^FREQUENCY NET "{role}"[^\n]*\n?', '', pins, flags=re.M)
        if count!=1:raise ValueError(f'expected one source LPF constraint for {role}')
    pins=''.join(f'FREQUENCY NET "{b["name"]}" {b["mhz"]:.6f} MHz;\n' for b in bindings)+pins
    a.output_json.write_text(json.dumps(netlist))
    a.output_lpf.write_text(pins)
    a.manifest.write_text(json.dumps({'clocks':bindings},indent=2)+'\n')
    for b in bindings:print(f'Bound {", ".join(b["roles"])}: {b["name"]} @ {b["mhz"]} MHz')


if __name__=='__main__':main()
