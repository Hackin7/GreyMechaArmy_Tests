"""Prepare a GBA menu app bundle without accessing or resetting the badge."""
import argparse
import ast
import hashlib
import json
import shutil
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
GB_BADGE = PROJECT.parent / 'gameboy_gbc/badge'
HOOK = """# GBA clean-reset install/launch; run before menu hardware owns pins.
import sys
_gba_path_added = '/apps/gba' not in sys.path
if _gba_path_added:
    sys.path.insert(0, '/apps/gba')
try:
    import gba_boot
    gba_boot.handle_pending()
finally:
    if _gba_path_added:
        sys.path.remove('/apps/gba')

"""


def patch_root(source):
    if HOOK not in source and 'gba_boot.handle_pending()' in source:
        old_hook = "# GBA clean-reset install/launch; run before menu hardware owns pins.\nimport sys\nif '/apps/gba' not in sys.path:\n    sys.path.insert(0, '/apps/gba')\nimport gba_boot\ngba_boot.handle_pending()\n\n"
        if source.count(old_hook) != 1:
            raise ValueError('Unrecognized GBA boot hook; cannot safely update it')
        source = source.replace(old_hook, HOOK, 1)
    if 'gba_boot.handle_pending()' not in source:
        anchor = '_nvm = microcontroller.nvm\n'
        if source.count(anchor) != 1:
            raise ValueError('Root code lacks the expected deferred-loader NVM anchor')
        source = source.replace(anchor, anchor + '\n' + HOOK, 1)
    ast.parse(source)
    if source.index('gba_boot.handle_pending()') > source.index('import hardware.main as hardware'):
        raise ValueError('GBA boot hook must run before normal hardware initialization')
    return source


def patch_registry(source):
    if 'import apps.gba.main' not in source:
        anchor = 'import apps.gameboy_gbc.main\n'
        if source.count(anchor) != 1:
            raise ValueError('App registry lacks the expected Game Boy import anchor')
        source = source.replace(anchor, anchor + 'import apps.gba.main\n', 1)
    if '"Game Boy Advance"' not in source:
        anchor = '        "Game Boy",\n'
        if source.count(anchor) != 1:
            raise ValueError('App registry lacks the expected Game Boy menu anchor')
        source = source.replace(anchor, anchor + '        "Game Boy Advance",\n', 1)
    if 'apps.gba.main.program_rom_app(hw_state)' not in source:
        anchor = '            if options[curr] == "Game Boy":\n'
        if source.count(anchor) != 1:
            raise ValueError('App registry lacks the expected Game Boy selection anchor')
        source = source.replace(anchor,
            '            if options[curr] == "Game Boy Advance":\n'
            '                apps.gba.main.program_rom_app(hw_state)\n' + anchor, 1)
    ast.parse(source)
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root-code', type=Path, default=GB_BADGE / 'code.py')
    parser.add_argument('--apps-init', type=Path, default=GB_BADGE / 'apps_init.py')
    parser.add_argument('--bit', type=Path, default=PROJECT / 'bitstreams/gba_psram_burst_25mhz.bit')
    parser.add_argument('--output', type=Path, default=PROJECT / 'build/gba-menu-app')
    parser.add_argument('--rom', type=Path, action='append', default=[])
    args = parser.parse_args()
    files = [(source, Path('apps/gba') / source.name) for source in (PROJECT / 'badge').glob('*.py')]
    files += [(args.bit, Path('apps/gba/gba.bit'))]
    for name in ('open_bios.bin', 'BIOS_SOURCE.txt', 'BIOS_LICENSE.txt', 'diagnostic.gba',
                 'bld_demo.gba', 'BLD_DEMO_SOURCE.txt', 'BLD_DEMO_LICENSE.txt'):
        files.append((PROJECT / 'build/roms' / name, Path('apps/gba') / name))
    files += [(rom, Path('apps/gba/games') / rom.name) for rom in args.rom]
    files += [(source, Path('hardware/fpga') / source.name) for source in (GB_BADGE / 'hardware/fpga').glob('*.py')]
    for source, destination in files:
        if not source.is_file():
            raise FileNotFoundError(source)
        if source in args.rom and (source.suffix.lower() != '.gba' or not 192 <= source.stat().st_size <= 8 * 1024 * 1024):
            raise ValueError('Unsupported ROM: ' + str(source))
    root = patch_root(args.root_code.read_text(encoding='utf-8-sig'))
    registry = patch_registry(args.apps_init.read_text(encoding='utf-8-sig'))
    for source, destination in files:
        target = args.output / destination
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.suffix == ".py":
            target.write_text(source.read_text(encoding="utf-8-sig"), encoding="utf-8")
        else:
            shutil.copy2(source, target)
    (args.output / 'code.py').write_text(root, encoding='utf-8')
    (args.output / 'apps/__init__.py').write_text(registry, encoding='utf-8')
    (args.output / 'apps/gba/games').mkdir(exist_ok=True)
    manifest = {'hardware_tested': False, 'root_source': str(args.root_code),
                'registry_source': str(args.apps_init),
                'root_source_sha256': hashlib.sha256(args.root_code.read_bytes()).hexdigest(),
                'registry_source_sha256': hashlib.sha256(args.apps_init.read_bytes()).hexdigest(),
                'files': {}}
    for target in sorted(args.output.rglob('*')):
        if target.is_file() and target.name != 'bundle-manifest.json':
            if target.suffix == '.py':
                ast.parse(target.read_text(encoding='utf-8-sig'))
            manifest['files'][str(target.relative_to(args.output)).replace('\\', '/')] = hashlib.sha256(target.read_bytes()).hexdigest()
    (args.output / 'bundle-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('GBA_APP_BUNDLE_READY', args.output, len(manifest['files']), 'files; hardware validation pending')


if __name__ == '__main__':
    main()
