"""Check and print nextpnr resource/frequency results before packing a bitstream."""
import json
from pathlib import Path

report=json.loads(Path('build/timing.json').read_text())
for name,values in sorted(report['fmax'].items()):
    print('{}: achieved {:.2f} MHz, required {:.2f} MHz'.format(
        name,values['achieved'],values['constraint']))
    if values['achieved']<values['constraint']:
        raise RuntimeError('Clock failed timing: '+name)
if len(report['fmax'])!=2:
    raise RuntimeError('Expected two constrained clock domains')
for name,values in sorted(report['utilization'].items()):
    if values['used']>values['available']:
        raise RuntimeError('Resource limit exceeded: '+name)
    if name in ('DP16KD','MULT18X18D','TRELLIS_COMB','TRELLIS_FF'):
        print('{}: {}/{}'.format(name,values['used'],values['available']))
