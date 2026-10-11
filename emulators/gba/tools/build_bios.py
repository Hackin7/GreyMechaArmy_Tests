#!/usr/bin/env python3
"""Build the GPL open BIOS with arm-none-eabi-gcc and pinned libtonc.

Only downloaded source and generated objects are placed in the build directory.
No commercial BIOS is needed. Run under Linux/WSL with the ARM compiler on PATH.
"""
import argparse
import hashlib
import subprocess
from pathlib import Path

BIOS = ('https://github.com/ez-me/gba-bios.git', 'bde9138f6dcb70b9a9ffe3f26a7307733775500e')
TONC = ('https://github.com/devkitPro/libtonc.git', 'ccc03fa321e56f51aed5e2ee1d6e3df3d1cbc803')


def run(*args):
    subprocess.run([str(a) for a in args], check=True)


def checkout(folder, spec):
    if not (folder / '.git').exists():
        run('git', 'clone', spec[0], folder)
    run('git', '-C', folder, 'checkout', '--detach', spec[1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sources', type=Path, default=Path('build/reference'))
    parser.add_argument('--output', type=Path, default=Path('build/roms'))
    parser.add_argument('--boot-logo', action='store_true', help='Retain the upstream two-second splash screen')
    args = parser.parse_args()
    sources, output = args.sources.resolve(), args.output.resolve()
    sources.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    bios, tonc = sources / 'bios', sources / 'tonc'
    checkout(bios, BIOS)
    checkout(tonc, TONC)
    objects = output / 'bios-objects'
    objects.mkdir(exist_ok=True)
    common = ['-mcpu=arm7tdmi', '-mthumb-interwork', '-O2', '-ffreestanding',
              '-fno-strict-aliasing', '-fcommon', '-I' + str(tonc / 'include')]
    tonc_objects = []
    for src in sorted(list((tonc / 'src').rglob('*.c')) + list((tonc / 'asm').glob('*.s'))):
        if 'tte' in src.parts or 'font' in src.parts or 'pre1.3' in src.parts:
            continue  # BIOS uses the core/math library, no stdio console hook.
        obj = objects / ('tonc_' + '_'.join(src.relative_to(tonc).parts) + '.o')
        mode = '-marm' if '.iwram.' in src.name else '-mthumb'
        language = ['-x', 'assembler-with-cpp'] if src.suffix == '.s' else []
        run('arm-none-eabi-gcc', *common, mode, *language, '-c', src, '-o', obj)
        tonc_objects.append(obj)
    library = objects / 'libtonc.a'
    run('arm-none-eabi-ar', 'rcs', library, *tonc_objects)
    bios_objects = []
    for src in sorted((bios / 'source').glob('*')):
        if src.suffix not in ('.s', '.c'):
            continue
        obj = objects / (src.name + '.o')
        mode = '-marm' if '.arm.' in src.name or src.suffix == '.s' else '-mthumb'
        if src.name == 'logo.c' and not args.boot_logo:
            text = src.read_text()
            text = text[:text.index('void DrawLogo()')] + 'void DrawLogo() { swi_RegisterRamReset(0xFF); }\n'
            src = objects / 'logo_without_splash.c'
            src.write_text(text)
        run('arm-none-eabi-gcc', *common, '-I' + str(bios / 'source'), mode, '-c', src, '-o', obj)
        bios_objects.append(obj)
    # The upstream linker file references undeclared RAM regions. Define them
    # explicitly; retain the upstream sections and BIOS entry address.
    script = (bios / 'specs/bios.ld').read_text()
    script = script.replace('bios\t: ORIGIN = 0x00000000, LENGTH = 128K',
                            'bios : ORIGIN = 0, LENGTH = 16K\n'
                            'ewram : ORIGIN = 0x02000000, LENGTH = 256K\n'
                            'iwram : ORIGIN = 0x03000000, LENGTH = 32K')
    link = objects / 'bios.ld'
    link.write_text(script)
    elf = output / 'open_bios.elf'
    run('arm-none-eabi-gcc', '-mcpu=arm7tdmi', '-mthumb-interwork', '-nostartfiles',
        '-nostdlib', '-T', link, *bios_objects, library, '-lgcc', '-o', elf)
    binary = output / 'open_bios.bin'
    run('arm-none-eabi-objcopy', '-O', 'binary', '--pad-to', '0x4000', elf, binary)
    if binary.stat().st_size != 16384:
        raise RuntimeError('BIOS must be exactly 16384 bytes')
    (output / 'BIOS_LICENSE.txt').write_bytes((bios / 'LICENSE').read_bytes())
    (output / 'BIOS_SOURCE.txt').write_text(
        '\n'.join([BIOS[0], BIOS[1], TONC[0], TONC[1],
                   'boot_logo=' + str(args.boot_logo),
                   'Boot modification: skip DrawLogo animation; retain RegisterRamReset(0xFF).',
                   'sha256=' + hashlib.sha256(binary.read_bytes()).hexdigest()]) + '\n')
    print('BIOS:', binary)


if __name__ == '__main__':
    main()
