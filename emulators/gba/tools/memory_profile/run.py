"""Run fixed software-memory profiles; run this script inside WSL/Linux."""
import argparse
import hashlib
import json
import subprocess
import time
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
REVISION = '26b7884bc25a5933960f3cdcd98bac1ae14d42e2'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, default=Path('/tmp/greymecha_gba_memory_profile/gba-memory-profile'))
    parser.add_argument('--control-binary', type=Path)
    parser.add_argument('--output', type=Path, default=PROJECT / 'build/memory-profile')
    parser.add_argument('--rgb-rom', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    bios = PROJECT / 'build/roms/open_bios.bin'
    roms = {'diagnostic': PROJECT / 'build/roms/diagnostic.gba',
            'bld_demo': PROJECT / 'build/roms/bld_demo.gba', 'rgb': args.rgb_rom}
    subprocess.run([str(args.binary), '--self-test'], check=True)
    for name, rom in roms.items():
        for mode in ('open_bios', 'hle_control'):
            path = args.output / (name + '-' + mode + '.json')
            bios_arg = str(bios) if mode == 'open_bios' else 'hle'
            started = time.monotonic()
            with path.with_suffix('.log').open('w') as log:
                subprocess.run([str(args.binary), str(rom), bios_arg, str(path), '180'],
                               stdout=log, stderr=subprocess.STDOUT, check=True)
            result = json.loads(path.read_text())
            result['metadata'] = {
                'emulator': 'mGBA 0.10.5', 'source_revision': REVISION,
                'rom_name': rom.name, 'rom_sha256': hashlib.sha256(rom.read_bytes()).hexdigest(),
                'bios_mode': mode, 'bios_sha256': hashlib.sha256(bios.read_bytes()).hexdigest() if mode == 'open_bios' else None,
                'frames_requested': 180, 'host_elapsed_seconds': time.monotonic() - started,
                'idle_loop_optimization': 'disabled', 'unchanged_scanline_reuse': 'disabled',
                'rom_loader': 'forced_cartridge_without_logo_crc_skip',
                'inputs': '0..89 released; 90..109 R; 110..129 released; 130..149 Left; 150..169 Up; 170..179 A',
                'graphics_scope': 'software renderer VRAM loads, including byte-indexed affine/bitmap reads',
                'graphics_limitations': 'mGBA tilemap/decoded-palette/OAM caching and access order differ from FPGA; no predicted FPGA FPS',
                'vram_models': 'Lower 64 KiB only; CPU/DMA writes invalidate; no write allocation. filter 0=unified,1=PPU-only,2=CPU-only',
                'tiny_graphics_model': '16-byte fully associative LRU approximation, not exact four-requester FPGA cache',
            }
            if args.control_binary:
                control = args.output / (name + '-' + mode + '-unhooked.json')
                with control.with_suffix('.log').open('w') as log:
                    subprocess.run([str(args.control_binary), str(rom), bios_arg, str(control), '180'],
                                   stdout=log, stderr=subprocess.STDOUT, check=True)
                reference = json.loads(control.read_text())
                fields = ('frames', 'final_pc', 'state_checksums', 'diagnostic_save_first_48')
                matches = {field: result[field] == reference[field] for field in fields}
                if not all(matches.values()):
                    raise RuntimeError('Profiling changed emulator state: ' + repr(matches))
                result['metadata']['unhooked_control_matches'] = matches
            path.write_text(json.dumps(result, indent=2) + '\n')
            print('PROFILE_COMPLETE', name, mode, 'frames', result['frames'], flush=True)


if __name__ == '__main__':
    main()
