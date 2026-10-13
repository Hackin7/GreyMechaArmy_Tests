#!/usr/bin/env python3
"""Map matched generated CPU subsystems without changing board or routing jobs."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


def extract(source):
    modules={m[1]:m[0] for m in re.finditer(r'^module\s+(\w+)\b.*?^endmodule\s*',source,re.M|re.S)}
    cpus=[name for name in modules if name.startswith('gba_cpu_Barch_')]
    if len(cpus)!=1: raise ValueError('expected one generated CPU module')
    needed={cpus[0]}; pending=list(needed)
    while pending:
        parent=pending.pop()
        instances=set(re.findall(r'^\s*(\w+)\s+[^\s(]+\s*\(',modules[parent],re.M))
        for name in (instances & modules.keys())-needed:
            needed.add(name); pending.append(name)
    cpu=cpus[0]
    header=modules[cpu].split(');',1)[0]
    ports=[]; connections=[]
    for match in re.finditer(r'\b(input|output)\s+(\[[^\]]+\]\s*)?(\\[^\s]+|\w+)',header):
        direction,width,name=match.groups(); width=width or ''
        if name.startswith('\\savestate_bus'):
            actual='ss_reset' if name=='\\savestate_bus[rst]' else "'0" if direction=='input' else ''
        else:
            ports.append(f'{direction} {width}{name}'); actual=name
        connections.append(f'.{name} ({actual})')
    ports.append('input ss_reset')
    wrapper='module cpu_subsystem('+','.join(ports)+');\n'+cpu+' cpu('+','.join(connections)+');\nendmodule\n'
    return 'cpu_subsystem', '\n'.join(modules[n] for n in sorted(needed))+'\n'+wrapper


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('baseline',type=Path); p.add_argument('candidate',type=Path)
    p.add_argument('--work',type=Path,default=Path('/tmp/gba-cpu-subsystem-area'))
    args=p.parse_args(); w=args.work.resolve(); w.mkdir(parents=True,exist_ok=True)
    results={'inputs':{
        'baseline_sha256':hashlib.sha256(args.baseline.read_bytes()).hexdigest(),
        'candidate_sha256':hashlib.sha256(args.candidate.read_bytes()).hexdigest(),
        'mapping_flags':'-noccu2 -nowidelut -no-rw-check',
        'abc_script_sha256':hashlib.sha256(Path('tools/ecp5_area.abc').read_bytes()).hexdigest(),
        'scope':'CPU subsystem with unused savestate transfers disabled; not full-board packed sites'}}
    for label,path in [('baseline',args.baseline),('candidate',args.candidate)]:
        name,source=extract(path.read_text())
        v=w/(label+'.v'); v.write_text(source)
        mapped=w/(label+'.json')
        with (w/(label+'.log')).open('w') as log:
            subprocess.run(['yosys','-Q','-T','-p',
                f'read_verilog -sv {v}; scratchpad -set abc9.script tools/ecp5_area.abc; '
                f'synth_ecp5 -top {name} -noccu2 -nowidelut -no-rw-check; check -assert; stat; write_json {mapped}'],
                check=True,stdout=log,stderr=log)
        cells=json.loads(mapped.read_text())['modules'][name]['cells']
        counts={}
        for cell in cells.values(): counts[cell['type']]=counts.get(cell['type'],0)+1
        results[label]=counts
        print(label,json.dumps(counts),flush=True)
    (w/'results.json').write_text(json.dumps(results,indent=2)+'\n')


if __name__=='__main__': main()
