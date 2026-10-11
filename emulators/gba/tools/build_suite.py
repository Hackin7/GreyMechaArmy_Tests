#!/usr/bin/env python3
"""Build the pinned mGBA autorun test ROM with an installed devkitPro SDK."""
import argparse
import hashlib
import os
import shutil
import subprocess
from pathlib import Path

COMMIT = '2a8eca19d896720cfcd6a2da400f7ab722ddd60c'
PROJECT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sources', type=Path, default=Path('/tmp/greymecha_gba_sources'))
    parser.add_argument('--sdk', type=Path)
    args = parser.parse_args()
    sdk = args.sdk or Path(os.environ.get('DEVKITPRO', '/opt/devkitpro'))
    if not (sdk / 'devkitARM/bin/arm-none-eabi-gcc').exists():
        sdk = args.sources / 'sdk/opt/devkitpro'
    if not (sdk / 'devkitARM/bin/arm-none-eabi-gcc').exists():
        raise SystemExit('Set DEVKITPRO or --sdk to a devkitPro SDK with devkitARM, libgba and libtonc')
    suite = args.sources / 'suite'
    args.sources.mkdir(parents=True, exist_ok=True)
    if not (suite / '.git').exists():
        run('git', 'clone', 'https://github.com/mgba-emu/suite.git', suite)
    run('git', '-C', suite, 'checkout', '--detach', COMMIT)
    patch_source = PROJECT / 'vendor/openfpga-GBA/benchmarks/mgba-suite/mgba-suite-bench.patch'
    patch = args.sources / 'suite-bench.patch'
    patch.write_bytes(patch_source.read_bytes().replace(b'\r\n', b'\n'))
    result = subprocess.run(['git', '-C', str(suite), 'apply', '--check', str(patch.resolve())], capture_output=True)
    if result.returncode == 0:
        run('git', '-C', suite, 'apply', patch.resolve())
    else:
        run('git', '-C', suite, 'apply', '--reverse', '--check', patch.resolve())
    env = os.environ.copy()
    env['DEVKITPRO'] = str(sdk.resolve())
    env['DEVKITARM'] = str((sdk / 'devkitARM').resolve())
    env['PATH'] = str(sdk / 'tools/bin') + ':' + str(sdk / 'devkitARM/bin') + ':' + env['PATH']
    run('make', 'clean', cwd=suite, env=env)
    run('make', '-j4', 'BENCH_AUTORUN=1', 'BENCH_SUITE_COMMIT=' + COMMIT, cwd=suite, env=env)
    output = PROJECT / 'build/roms'
    output.mkdir(parents=True, exist_ok=True)
    target = output / 'suite-bench.gba'
    shutil.copyfile(suite / 'suite.gba', target)
    shutil.copyfile(suite / 'LICENSE', output / 'SUITE_LICENSE.txt')
    (output / 'SUITE_SOURCE.txt').write_text(
        'https://github.com/mgba-emu/suite\ncommit: ' + COMMIT + '\n'
        'autorun patch: vendor/openfpga-GBA/benchmarks/mgba-suite/mgba-suite-bench.patch\n'
        'patch SHA256: ' + hashlib.sha256(patch.read_bytes()).hexdigest() + '\n'
        'ROM SHA256: ' + hashlib.sha256(target.read_bytes()).hexdigest() + '\n')
    print(target)


if __name__ == '__main__':
    main()
