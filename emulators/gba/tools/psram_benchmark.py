#!/usr/bin/env python3
"""Test the GBA PSRAM PHY on hardware, then restore the existing GBA image.

The benchmark replaces all volatile PSRAM contents. It does not program ROM
flash or change the normal GBA bitstream file. FPGA cycle counters, rather
than USB round-trip time, measure a full 8 MiB write and read/verify pass.
"""
import argparse
import hashlib
import json
import os
import shutil
import time
from pathlib import Path
from hardware_test import Console, PROJECT, preflight


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port',default='COM9')
    parser.add_argument('--drive',type=Path,default=Path('E:/'))
    parser.add_argument('--bit',type=Path,default=PROJECT/'build/psram-benchmark/gba-psram-baseline.bit')
    parser.add_argument('--core-hz',type=float,
                        help='Override automatic GP12 frequency calibration')
    parser.add_argument('--spi-core-ratio',type=float,default=1.25,
                        help='Default asynchronous PHY: 1.25; PSRAM_BENCH_ASYNC=0: 0.5')
    parser.add_argument('--write-core-ratio',type=float)
    parser.add_argument('--log-name',default='psram-benchmark')
    args=parser.parse_args()
    app=args.drive/'apps/gba'
    restore=app/'gba.bit'
    staged=app/'gba-psram-benchmark.bit'
    if not args.bit.is_file() or not restore.is_file():
        raise FileNotFoundError('Both benchmark and original device GBA bitstreams are required')
    if args.core_hz is not None and args.core_hz<=0:
        raise ValueError('Core frequency must be positive')
    restore_hash=hashlib.sha256(restore.read_bytes()).hexdigest()
    previous=staged.read_bytes() if staged.exists() else None
    out=PROJECT/('build/hardware/'+args.log_name+'.json')
    log=dict(bit_sha256=hashlib.sha256(args.bit.read_bytes()).hexdigest(),
             restore_sha256=restore_hash,core_hz=args.core_hz,bytes_per_phase=8*1024*1024,
             clock_source='override' if args.core_hz else 'RP2350 PulseIn, core clock / 65536 on GP12')
    console=Console(args.port)
    try:
        shutil.copy2(args.bit,staged)
        with staged.open('ab') as stream:stream.flush();os.fsync(stream.fileno())
        console.upload('/apps/gba/gba-psram-benchmark.bit')
        console.connect()
        preflight(console,log)
        if args.core_hz is None:
            source="""import pulseio, board
_samples=[]
for _sample in range(3):
    _pulses=pulseio.PulseIn(board.GP12,maxlen=258,idle_state=False)
    try:
        _deadline=time.monotonic()+3
        while len(_pulses)<258:
            if time.monotonic()>_deadline: raise RuntimeError('Clock calibration timeout')
            time.sleep(0.001)
        _pulses.pause()
        _samples.append(128*65536*1000000/sum(_pulses[_i] for _i in range(1,257)))
    finally:
        _pulses.deinit()
print(json.dumps(sorted(_samples)))
"""
            samples=json.loads(console.execute(source,timeout=15).strip())
            args.core_hz=samples[1]
            log.update(clock_samples_hz=samples,core_hz=args.core_hz)
        log['spi_hz']=args.core_hz*args.spi_core_ratio
        log['write_spi_hz']=args.core_hz*(args.write_core_ratio if args.write_core_ratio is not None else args.spi_core_ratio)
        # Start only the autonomous benchmark, without BIOS/ROM staging.
        console.execute('_gba_host.command(3)\n')
        deadline=time.monotonic()+120
        last_phase=-1
        while time.monotonic()<deadline:
            status=console.status()
            if status['pc']>>28!=last_phase:
                print('PSRAM_BENCH_STATUS',status,flush=True);last_phase=status['pc']>>28
            if status['ram_fault'] or status['error']:
                raise RuntimeError('PSRAM benchmark transport fault: '+repr(status))
            if status['pc']>>28==3:
                if status['pc']&(1<<27):
                    raise RuntimeError('Full-memory comparison failed: '+repr(status))
                write_cycles,read_cycles=status['frames'],status['flash_misses']
                if not write_cycles or not read_cycles:
                    raise RuntimeError('Missing benchmark cycle counters')
                log.update(result='pass',final_status=status,write_cycles=write_cycles,
                           read_cycles=read_cycles,
                           write_mb_s=8*1024*1024*args.core_hz/write_cycles/1e6,
                           read_mb_s=8*1024*1024*args.core_hz/read_cycles/1e6)
                print('PSRAM_BENCH_PASS',json.dumps(log),flush=True)
                break
            time.sleep(0.2)
        else:
            raise RuntimeError('PSRAM benchmark did not finish within 120 seconds')
    except Exception as exc:
        log.update(result='failed',error=str(exc))
        raise
    finally:
        try:
            if console.console is not None:
                console.execute('_gba_spi.deinit()\n')
            if hashlib.sha256(restore.read_bytes()).hexdigest()!=restore_hash:
                raise RuntimeError('Original device bitstream changed during the benchmark')
            console.upload()
            console.connect()
            log['restored_status']=console.status()
            log['restored_bitstream']=True
            console.execute('_gba_spi.deinit()\n')
        except Exception as exc:
            log['restored_bitstream']=False
            log['restore_error']=str(exc)
            raise
        finally:
            console.close()
            if previous is None:
                if staged.exists(): staged.unlink()
            else:
                staged.write_bytes(previous)
            out.parent.mkdir(parents=True,exist_ok=True)
            out.write_text(json.dumps(log,indent=2),encoding='utf-8')


if __name__=='__main__':
    main()
