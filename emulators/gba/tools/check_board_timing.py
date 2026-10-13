#!/usr/bin/env python3
"""Reject dropped clock constraints and verify every reported clock target."""
import argparse
import json
from pathlib import Path
import re


def check_constraints(log,bindings):
    if re.search(r'ignoring clock constraint',log,re.I):
        raise ValueError('router ignored a clock constraint')
    for clock in bindings:
        match=re.search(r"constraining clock net '"+re.escape(clock['name'])+r"' to ([\d.]+) MHz",log)
        if match is None or abs(float(match[1])-clock['mhz'])>0.01:
            raise ValueError(f'clock target not applied: {clock}')


def check_fmax(report,bindings):
    fmax=report.get('fmax',{})
    for clock in bindings:
        values=[value for name,value in fmax.items() if name==clock['name'] or name=='$glbnet$'+clock['name']]
        if len(values)!=1:raise ValueError(f'missing timing report for {clock["name"]}')
        value=values[0]
        if abs(value['constraint']-clock['mhz'])>0.01 or value['achieved']<value['constraint']:
            raise ValueError(f'failed timing: {clock["name"]}: {value}')
    for name,value in fmax.items():
        if value['achieved']<value['constraint']:raise ValueError(f'failed timing: {name}: {value}')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('manifest',type=Path)
    p.add_argument('log',type=Path)
    p.add_argument('--report',type=Path)
    a=p.parse_args()
    bindings=json.loads(a.manifest.read_text())['clocks']
    check_constraints(a.log.read_text(),bindings)
    if a.report:
        check_fmax(json.loads(a.report.read_text()),bindings)
    print('PASS board timing: all declared clock constraints applied'+(' and met' if a.report else ''))


if __name__=='__main__':main()
