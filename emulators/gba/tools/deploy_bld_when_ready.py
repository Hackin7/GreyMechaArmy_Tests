#!/usr/bin/env python3
"""Wait for the faster GBA route, then run the diagnostic and blending demo."""
import argparse
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path

PROJECT=Path(__file__).resolve().parents[1]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port',default='COM9')
    parser.add_argument('--drive',default='E:/')
    parser.add_argument('--build',type=Path,default=PROJECT/'build/psram-async-board')
    parser.add_argument('--wait-minutes',type=float,default=240)
    args=parser.parse_args()
    state_file=PROJECT/'build/hardware/bld-deployment-state.json'
    state_file.parent.mkdir(parents=True,exist_ok=True)
    state=dict(state='waiting_for_route',build=str(args.build),port=args.port)
    def update(value):
        state.update(value)
        state_file.write_text(json.dumps(state,indent=2)+'\n',encoding='utf-8')
        print(json.dumps(state),flush=True)
    update({})
    try:
        deadline=time.monotonic()+args.wait_minutes*60
        bit=args.build/'gba.bit'
        route_log=args.build/'board-nextpnr.log'
        report=args.build/'timing.json'
        while time.monotonic()<deadline:
            text=route_log.read_text(errors='replace') if route_log.exists() else ''
            if 'ERROR:' in text or 'Error:' in text:
                raise RuntimeError('FPGA routing failed; refusing deployment')
            if 'Program finished normally.' in text and bit.is_file() and report.is_file():
                size=bit.stat().st_size
                time.sleep(2)
                if size>100000 and bit.stat().st_size==size:
                    break
            time.sleep(5)
        else:
            raise RuntimeError('FPGA route did not complete within the waiting limit')
        timing=json.loads(report.read_text())
        clocks=timing.get('fmax',{})
        if not clocks:
            raise RuntimeError('Routing report has no clock timing results')
        for name,result in clocks.items():
            if result['achieved']<result['constraint']:
                raise RuntimeError('Routed timing failed for '+name)
        update(dict(state='testing_diagnostic',bit_sha256=hashlib.sha256(bit.read_bytes()).hexdigest()))
        runner=PROJECT/'tools/hardware_test.py'
        for action in ('diagnostic','demo'):
            update(dict(state='testing_'+action))
            with (PROJECT/'build/hardware'/('fast-'+action+'-run.log')).open('w',encoding='utf-8') as output:
                subprocess.run([sys.executable,'-u',str(runner),'--port',args.port,'--drive',args.drive,
                                '--bit',str(bit),action,'--minutes','3'],
                               cwd=PROJECT,stdout=output,stderr=subprocess.STDOUT,check=True)
        update(dict(state='demo_running',physical_screen='awaiting observation',
                    physical_buttons='awaiting observation'))
    except BaseException as exc:
        update(dict(state='failed',error=str(exc)))
        raise


if __name__=='__main__':
    main()
