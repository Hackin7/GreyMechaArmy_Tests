#!/usr/bin/env python3
"""Pack mapped ECP5 JSON and report resources without placement or routing."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('netlist',type=Path)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args(); args.output.parent.mkdir(parents=True,exist_ok=True)
    log=args.output.with_suffix('.log')
    command=['nextpnr-ecp5','--25k','--package','CABGA256','--speed','6',
             '--json',str(args.netlist),'--seed','1','--no-place','--no-route']
    with log.open('w') as f:
        subprocess.run(command,stdout=f,stderr=f,check=True)
    text=log.read_text()
    resources={name:{'used':int(used),'capacity':int(capacity)}
               for name,used,capacity in re.findall(r'Info:\s+(\w+):\s+(\d+)/\s*(\d+)',text)}
    if 'TRELLIS_COMB' not in resources:
        raise ValueError('missing packed resource report')
    report={'netlist_sha256':hashlib.sha256(args.netlist.read_bytes()).hexdigest(),
            'scope':'packing only; no placement, routing or timing acceptance',
            'command':command,'resources':resources}
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(resources['TRELLIS_COMB']))


if __name__=='__main__': main()
