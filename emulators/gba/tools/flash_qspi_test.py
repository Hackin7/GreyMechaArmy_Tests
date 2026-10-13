#!/usr/bin/env python3
"""Compare GBA SPI/quad cache reads with independent JTAG flash reads.

Temporarily loads read-only FPGA images. No erase/program or ROM install.
Restores the original volatile SR2 value and normal GBA bitstream in finally.
"""
import argparse
import hashlib
import json
import os
import shutil
import time
from pathlib import Path
from hardware_test import Console, PROJECT


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port',default='COM9')
    parser.add_argument('--drive',type=Path,default=Path('E:/'))
    parser.add_argument('--quad-bit',type=Path)
    parser.add_argument('--flash-ratio',type=float,default=2.5)
    parser.add_argument('--quad-cycles',type=int,default=4)
    parser.add_argument('--log-name',default='flash-qspi')
    parser.add_argument('--repeats',type=int,default=3)
    parser.add_argument('--extra-regions',type=int,default=0)
    parser.add_argument('--skip-spi',action='store_true')
    args=parser.parse_args()
    app=args.drive/'apps/gba'
    restore=app/'gba.bit'
    bits=[PROJECT/('build/flash-benchmark/gba-flash-%d.bit'%mode) for mode in (0,1)]
    if args.quad_bit is not None:bits[1]=args.quad_bit
    for path in bits+[restore,args.drive/'code.py']:
        if not path.is_file():raise FileNotFoundError(str(path))
    log=dict(result='running',modes=[],regions=[])
    hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in (restore,args.drive/'code.py')}
    console=Console(args.port)
    previous={}
    original_sr2=None
    # Exercise nonblank ROM bytes, cache/page/64 KiB boundaries and highest address.
    regions=[(0,2048),(0xf80,512),(0xff80,512),(0x1ff80,512),(0x7fff00,256)]
    for index in range(args.extra_regions):
        address=((index*0x9e3779+0x34567)&0x7fffff)&~255
        regions.append((address,256))
    if args.repeats<1 or not 0<=args.extra_regions<=64:raise ValueError('Invalid stress parameters')
    output=PROJECT/('build/hardware/'+args.log_name+'.json')
    output.parent.mkdir(parents=True,exist_ok=True)
    try:
        result=console.execute("from hardware.fpga import ecp5f as _f\nimport time,binascii\n"
            "_f.flash_open()\n"
            "try:\n"
            "    _sr=[]\n"
            "    for _cmd in (5,53,21):\n"
            "        _v=bytearray([_cmd,0]);_f._dr_response(_v);_sr.append(_v[1])\n"
            "    print('STATUS',_sr)\n"
            "    for _a,_n in %r:\n"
            "        _v=bytearray(_n);_f.flash_read_block(_v,0x100000+_a)\n"
            "        print(_a,binascii.hexlify(_v).decode())\n"
            "finally:\n    _f.flash_close()\n" % regions,timeout=60)
        print(result.splitlines()[0],flush=True)
        lines=result.strip().splitlines()
        status=json.loads(lines[0].split(' ',1)[1]);original_sr2=status[1]
        log['original_status_registers']=status
        references={int(line.split()[0]):bytes.fromhex(line.split()[1]) for line in lines[1:]}
        if len(references)!=len(regions) or len(set(references[0]))<8:
            raise RuntimeError('Independent reference missing or ROM header is blank')
        for mode in range(1 if args.skip_spi else 0,2):
            source=bits[mode]
            staged=app/'gba-flash-test.bit'
            if staged not in previous:previous[staged]=staged.read_bytes() if staged.exists() else None
            shutil.copy2(source,staged)
            with staged.open('ab') as stream:
                stream.flush();os.fsync(stream.fileno())
            console.upload('/apps/gba/'+staged.name)
            console.connect()
            for attempt in range(3):
                try:
                    status=console.status();break
                except RuntimeError:
                    if attempt==2:raise
                    console.execute('_gba_spi.deinit()\n')
                    console.upload('/apps/gba/'+staged.name);console.connect()
            deadline=time.monotonic()+5
            while True:
                status=console.status()
                if status['ram_fault']:raise RuntimeError('QE initialization failed')
                if status['ram_ready']:break
                if time.monotonic()>deadline:raise RuntimeError('Reader initialization timeout')
            if status['device_id']!=0x515350 or status['pc']!=mode:
                raise RuntimeError('Unexpected test image: '+repr(status))
            # Calibrate core clock using the same GP12 reference as the PSRAM test.
            samples=json.loads(console.execute("import pulseio,board\n_samples=[]\n"
                "for _ in range(3):\n"
                "    _p=pulseio.PulseIn(board.GP12,maxlen=258,idle_state=False)\n"
                "    try:\n"
                "        _end=time.monotonic()+3\n"
                "        while len(_p)<258 and time.monotonic()<_end:time.sleep(0.001)\n"
                "        if len(_p)<258:raise RuntimeError('Clock capture timeout')\n"
                "        _p.pause()\n"
                "        _samples.append(128*65536*1000000/sum(_p[_i] for _i in range(1,257)))\n"
                "    finally:_p.deinit()\n"
                "print(json.dumps(_samples))\n").strip())
            before=console.status();total=0
            for repeat in range(args.repeats):
                for address,length in regions:
                    received=bytes.fromhex(console.execute(
                        "print(binascii.hexlify(_gba_host.read(%d,%d)).decode())\n" % (address,length),
                        timeout=60).strip())
                    if received!=references[address]:
                        first=next(i for i,(a,b) in enumerate(zip(received,references[address])) if a!=b) if len(received)==length else 0
                        raise RuntimeError('Mode %d mismatch at cartridge byte 0x%x: got %s expected %s'%(mode,address+first,received[first:first+8].hex(),references[address][first:first+8].hex()))
                    total+=length
            after=console.status();cycles=after['frames']-before['frames']
            core_hz=sorted(samples)[1]
            entry=dict(mode='qspi' if mode else 'spi',bytes_verified=total,
                       bit_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                       core_hz=core_hz,sck_hz=core_hz*(args.flash_ratio if mode else 2.5)/(args.quad_cycles if mode else 4),
                       clock_samples_hz=samples,cache_service_cycles=cycles,
                       cache_service_mb_s=total*core_hz/cycles/1e6,
                       cache_misses=after['flash_misses']-before['flash_misses'])
            log['modes'].append(entry);print('FLASH_READ_PASS',json.dumps(entry),flush=True)
            console.execute('_gba_spi.deinit()\n')
        log['regions']=[dict(address=a,size=n,sha256=hashlib.sha256(references[a]).hexdigest()) for a,n in regions]
        log['result']='pass'
    except Exception as exc:
        log.update(result='failed',error=str(exc));raise
    finally:
        try:
            if console.console is not None:
                console.execute("if '_gba_spi' in globals():_gba_spi.deinit()\n")
            if original_sr2 is not None:
                status=console.execute("from hardware.fpga import ecp5f as _f\n_f.flash_open()\n"
                    "try:\n"
                    "    _f._dr_write(bytearray([0x50]))\n"
                    "    _f._dr_write(bytearray([0x31,%d]))\n"
                    "    time.sleep(0.001)\n"
                    "    _v=bytearray([0x35,0]);_f._dr_response(_v);print(_v[1])\n"
                    "finally:\n    _f.flash_close()\n"%original_sr2)
                if int(status.strip())!=original_sr2:raise RuntimeError('SR2 restoration failed')
                log['restored_sr2']=original_sr2
            for path,digest in hashes.items():
                if hashlib.sha256(Path(path).read_bytes()).hexdigest()!=digest:
                    raise RuntimeError('Preserved device file changed: '+path)
            console.upload();console.connect();log['restored_status']=console.status()
            log['restored_bit_sha256']=hashes[str(restore)]
        finally:
            console.close()
            for path,data in previous.items():
                if data is None:
                    if path.exists():path.unlink()
                else:path.write_bytes(data)
            output.write_text(json.dumps(log,indent=2)+'\n')
            print('LOG',output,flush=True)


if __name__=='__main__':main()
