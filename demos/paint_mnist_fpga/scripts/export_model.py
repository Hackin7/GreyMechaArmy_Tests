"""Export untouched COE constants, binary images and full-neuron integer oracles."""
import argparse
import hashlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'mnist_c'))
from export_model import read_coe, reference


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--resources', required=True, type=Path)
    p.add_argument('--out', type=Path, default=Path('build/generated'))
    a=p.parse_args()
    weights=read_coe(a.resources/'weights.coe', 50890)
    cases=[read_coe(a.resources/'00.coe',784,True), [0]*784, [1]*784,
           [int(i%29==0 or i%28==14) for i in range(784)],
           [int((i*73+19)%101<37) for i in range(784)],
           [int(i==406) for i in range(784)]]
    a.out.mkdir(parents=True,exist_ok=True)
    (a.out/'weights.mem').write_text('\n'.join('{:04x}'.format(v&65535) for v in weights)+'\n')
    (a.out/'images.mem').write_text('\n'.join(str(v) for image in cases for v in image)+'\n')
    oracle=[reference(image,weights) for image in cases]
    (a.out/'expected.mem').write_text('\n'.join('{:016x}'.format(v&((1<<64)-1))
                                                for values,digit in oracle for v in values)+'\n')
    (a.out/'digits.mem').write_text('\n'.join('{:x}'.format(digit) for _,digit in oracle)+'\n')
    (a.out/'model.sha256').write_text(hashlib.sha256((a.resources/'weights.coe').read_bytes()).hexdigest()+'\n')
    print('Exported 50890 original constants and 6 oracle images')


if __name__=='__main__':
    main()
