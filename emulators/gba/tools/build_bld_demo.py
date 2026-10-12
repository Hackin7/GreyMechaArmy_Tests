#!/usr/bin/env python3
"""Build the unmodified, pinned Tonc blending demo with the existing GBA SDK."""
import argparse
import hashlib
import json
import os
import shutil
import struct
import subprocess
from pathlib import Path

REPOSITORY='https://github.com/gbadev-org/libtonc-examples.git'
COMMIT='db70fa29a0baae12c5c7603426d8535ebb5cc6ed'
PROJECT=Path(__file__).resolve().parents[1]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sources',type=Path,default=Path('/tmp/greymecha_gba_sources'))
    parser.add_argument('--sdk',type=Path)
    args=parser.parse_args()
    sdk=args.sdk or Path(os.environ.get('DEVKITPRO','/opt/devkitpro'))
    if not (sdk/'devkitARM/bin/arm-none-eabi-gcc').is_file():
        sdk=args.sources/'sdk/opt/devkitpro'
    if not (sdk/'devkitARM/bin/arm-none-eabi-gcc').is_file():
        raise SystemExit('Set DEVKITPRO or --sdk to the installed devkitPro GBA SDK')
    source=args.sources/'tonc_examples'
    source.parent.mkdir(parents=True,exist_ok=True)
    if not (source/'.git').is_dir():
        subprocess.run(['git','clone',REPOSITORY,str(source)],check=True)
    subprocess.run(['git','-C',str(source),'checkout','--detach',COMMIT],check=True)
    env=os.environ.copy()
    env['DEVKITPRO']=str(sdk.resolve())
    env['DEVKITARM']=str((sdk/'devkitARM').resolve())
    env['PATH']=str(sdk/'tools/bin')+':'+str(sdk/'devkitARM/bin')+':'+env['PATH']
    demo=source/'ext/bld_demo'
    subprocess.run(['make','-j4'],cwd=demo,env=env,check=True)
    output=PROJECT/'build/roms'
    output.mkdir(parents=True,exist_ok=True)
    for name in ('bld_demo.gba','bld_demo.elf'):
        shutil.copy2(demo/name,output/name)
    shutil.copy2(demo/'build/bld_demo.map',output/'bld_demo.map')
    shutil.copy2(source/'LICENSE',output/'BLD_DEMO_LICENSE.txt')
    rom=(output/'bld_demo.gba').read_bytes()
    symbols=subprocess.check_output([str(sdk/'devkitARM/bin/arm-none-eabi-nm'),
                                     str(demo/'bld_demo.elf')],text=True)
    tile_symbol=next(line.split() for line in symbols.splitlines() if line.split()[-1:] == ['metrTiles'])
    tile_offset=int(tile_symbol[0],16)-0x08000000
    tiles=rom[tile_offset:tile_offset+2048]
    if len(tiles)!=2048:
        raise RuntimeError('Blending demo tile symbol is outside the cartridge')
    regions=[dict(name='Metroid background tiles',address=0x108000,hex=tiles.hex()),
             dict(name='Fence tile',address=0x108800,
                  hex=struct.pack('<8I',0x00012000,0x00012000,0x00022200,0x22220222,
                                  0x11122211,0x00112000,0x00012000,0x00012000).hex())]
    for row in range(8):
        regions.append(dict(name='Metroid tilemap row '+str(row),address=0x10f0e4+row*64,
                            hex=struct.pack('<8H',*(0x1000+row*8+column for column in range(8))).hex()))
    (output/'BLD_DEMO_EXPECTATIONS.json').write_text(json.dumps(
        dict(rom_sha256=hashlib.sha256(rom).hexdigest(),regions=regions,
             text_address=0x100000,text_size=19200),indent=2)+'\n')
    compiler=subprocess.check_output([str(sdk/'devkitARM/bin/arm-none-eabi-gcc'),'--version'],text=True)
    (output/'BLD_DEMO_SOURCE.txt').write_text(
        REPOSITORY+'\ncommit: '+COMMIT+'\nexample: ext/bld_demo\n'
        'Source modifications: none\ncompiler: '+compiler.splitlines()[0]+'\n'
        'libtonc.a SHA256: '+hashlib.sha256((sdk/'libtonc/lib/libtonc.a').read_bytes()).hexdigest()+'\n'
        'ROM SHA256: '+hashlib.sha256((output/'bld_demo.gba').read_bytes()).hexdigest()+'\n')
    print(output/'bld_demo.gba')


if __name__=='__main__':
    main()
