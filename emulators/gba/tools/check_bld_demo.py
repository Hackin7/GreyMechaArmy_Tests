"""Observe unmodified bld_demo graphics and controls through the GBA host."""
import hashlib
import json
import time
from pathlib import Path

PROJECT=Path(__file__).resolve().parents[1]


def wait_frames(console,count,timeout=60):
    start=console.status()['frames']
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        status=console.status()
        if status['ram_fault'] or status['overflow'] or status['error']:
            raise RuntimeError('Demo hardware fault: '+repr(status))
        if (status['frames']-start)&0xffffffff>=count:
            return status
        time.sleep(0.1)
    raise RuntimeError('Demo stopped advancing frames: '+repr(status))


def check_demo(console,log,out):
    expected=json.loads((PROJECT/'build/roms/BLD_DEMO_EXPECTATIONS.json').read_text())
    rom=(PROJECT/'build/roms/bld_demo.gba').read_bytes()
    if hashlib.sha256(rom).hexdigest()!=expected['rom_sha256']:
        raise RuntimeError('Demo verification metadata does not match the cartridge')
    log['demo']=dict(rom_sha256=expected['rom_sha256'],assets=[],controls=[],
                     physical_screen='requires observation',physical_buttons='requires observation')
    def stable_text():
        # printf erases/redraws the canvas each frame. Require matching
        # snapshots to avoid treating a partially redrawn canvas as input.
        previous=None
        for attempt in range(8):
            current=console.memory(expected['text_address'],expected['text_size'])
            if current==previous:return current
            previous=current
            wait_frames(console,2)
        raise RuntimeError('Demo text canvas did not settle for verification')
    # Startup code can already be in ROM while it is still preparing VRAM.
    deadline=time.monotonic()+90
    while True:
        wait_frames(console,2)
        mismatches=[]
        for region in expected['regions']:
            wanted=bytes.fromhex(region['hex'])
            actual=console.memory(region['address'],len(wanted))
            if actual!=wanted: mismatches.append(region['name'])
        if not mismatches:break
        if time.monotonic()>deadline:
            raise RuntimeError('Demo graphics initialization failed: '+repr(mismatches))
    log['demo']['assets']=[region['name'] for region in expected['regions']]
    # R cycles into alpha mode; holding Left lowers EVA. Both must update
    # the visible on-screen values in the character canvas.
    try:
        console.execute('_gba_host.keys(0)\n')
        wait_frames(console,3)
        # A resumed test may begin in any blend mode. Return to mode zero
        # before testing the mode-one transition.
        for tap in range(3):
            console.execute('_gba_host.keys(0x200)\n')
            wait_frames(console,3)
            console.execute('_gba_host.keys(0)\n')
            wait_frames(console,2)
        before=stable_text()
        (out/'bld-demo-text-before.bin').write_bytes(before)
        for name,mask,frames in [('R: next blend mode',0x100,3),('Left: lower EVA',0x20,16),
                                 ('Up: increase EVB',0x40,16)]:
            console.execute('_gba_host.keys(%d)\n'%mask)
            wait_frames(console,frames)
            console.execute('_gba_host.keys(0)\n')
            wait_frames(console,3)
            after=stable_text()
            (out/('bld-demo-text-'+str(len(log['demo']['controls']))+'.bin')).write_bytes(after)
            if after==before:
                raise RuntimeError('Demo on-screen values did not respond to '+name)
            log['demo']['controls'].append(dict(name=name,text_sha256=hashlib.sha256(after).hexdigest()))
            before=after
    finally:
        console.execute('_gba_host.keys(None)\n')
    # Measure a quiet interval, without pauses for host RAM reads.
    first=console.status();started=time.monotonic()
    time.sleep(10)
    last=console.status();elapsed=time.monotonic()-started
    delta=(last['frames']-first['frames'])&0xffffffff
    if delta==0:raise RuntimeError('Demo produced no frames during FPS observation')
    log['demo'].update(frames_observed=delta,observation_seconds=elapsed,
                       captured_fps=delta/elapsed,last_status=last)
