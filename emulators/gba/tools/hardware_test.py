#!/usr/bin/env python3
"""Deploy and test the GBA on GreyMecha over CircuitPython's USB raw REPL.

Examples:
  python tools/hardware_test.py --port COM9 --drive E:/ diagnostic
  python tools/hardware_test.py --port COM9 --drive E:/ suite --minutes 60
  python tools/hardware_test.py --port COM9 status

The FPGA cartridge region at 0x100000 is replaced by the selected test ROM.
Root code.py and the normal menu are preserved; the existing NVM loader is used.
"""
import argparse
import hashlib
import json
import shutil
import struct
import sys
import time
from pathlib import Path
import serial

PROJECT = Path(__file__).resolve().parents[1]
SUITE_PROGRESS_ROM_SHA256 = 'ba369e8bd9d7d532f5cd31deb4e05f324652b62056215487d79b89b81a0f1a7a'
sys.path.insert(0, str(PROJECT.parents[1] / 'io/fpga_psram_j1/scripts'))
from repl_run import read_until


class Console:
    def __init__(self, port):
        self.port = port
        self.console = None

    def close(self):
        if self.console is not None:
            console = self.console
            self.console = None
            try:
                console.write(b'\x02')
            except (serial.SerialException, OSError):
                pass
            finally:
                console.close()

    def execute(self, source, timeout=120, resets=False):
        # CircuitPython clears REPL globals when entering raw mode. Keep one
        # raw session open so the SPI pin owners and host survive each command.
        if self.console is None:
            self.console = serial.Serial(self.port, 115200, timeout=0.1)
            console = self.console
            console.write(b'\r\x03\x03')
            time.sleep(0.3)
            console.write(b'\x02\r\x03')
            time.sleep(0.3)
            console.reset_input_buffer()
            console.write(b'\x01')
            read_until(console, b'raw REPL; CTRL-B to exit\r\n>', 5)
        console = self.console
        encoded = source.encode()
        for offset in range(0, len(encoded), 128):
            console.write(encoded[offset:offset + 128])
            time.sleep(0.003)
        console.write(b'\x04')
        read_until(console, b'OK', 5)
        if resets:
            console.close()
            self.console = None
            return ''
        stdout = read_until(console, b'\x04', timeout)[:-1]
        stderr = read_until(console, b'\x04', 5)[:-1]
        read_until(console, b'>', 5)
        if stderr:
            raise RuntimeError(stderr.decode('utf-8', 'replace'))
        return stdout.decode('utf-8', 'replace')

    def upload(self, path='/apps/gba/gba.bit'):
        self.execute("import sys\nsys.path.insert(0,'/apps/gba')\n"
                     "from gba_app import deferred_upload\ndeferred_upload(%r)\n" % path, resets=True)
        deadline = time.monotonic() + 30
        # The badge's 6 MHz PIO loader also retires programming for 200 ms.
        # Let cold boot/upload finish before execute() sends any Ctrl-C.
        time.sleep(5)
        while time.monotonic() < deadline:
            time.sleep(1)
            try:
                output = self.execute("print('GBA_BOOT_REPL_READY')\n", timeout=5)
                if 'GBA_BOOT_REPL_READY' in output:
                    return
            except (serial.SerialException, OSError, RuntimeError):
                self.close()
                continue
        raise RuntimeError('Badge did not reconnect after bitstream upload')

    def connect(self):
        self.execute("import sys\nsys.path.insert(0,'/apps/gba')\n"
                     "from gba_app import GBAHost, BitBangSpi\n"
                     "import json, time, struct, binascii\n"
                     "_gba_spi=BitBangSpi()\n_gba_host=GBAHost(_gba_spi)\n")

    def status(self):
        return json.loads(self.execute("print(json.dumps(_gba_host.status()))\n").strip())

    def memory(self, address, size, save=False):
        result = self.execute("_gba_host.pause()\n"
                              "try:\n"
                              "    print(binascii.hexlify(_gba_host.read(%d,%d,save=%r)).decode())\n"
                              "finally:\n"
                              "    _gba_host.resume()\n" % (address, size, save), timeout=180)
        return bytes.fromhex(result.strip())

    def save(self, address, size):
        return self.memory(address,size,save=True)

    def suite_progress(self):
        # Symbols from the pinned suite.elf (ROM hash checked by the caller).
        result = self.execute(
            "_gba_host.pause()\n"
            "_info=_gba_host.read(0x400ac,8)\n"
            "_counts=_gba_host.read(0x42ea4,16)\n"
            "_gba_host.resume()\n"
            "print(binascii.hexlify(_info).decode(),binascii.hexlify(_counts).decode())\n")
        info, counts = [bytes.fromhex(item) for item in result.strip().split()]
        if info[:4] != b'Info':
            return dict(available=False, info_hex=info.hex())
        subtest, test, suite = struct.unpack_from('<HBB', info, 4)
        length, truncated, passed, total = struct.unpack('<4I', counts)
        return dict(available=True, suite=suite, test=test, subtest=subtest,
                    completed_passes=passed, completed_results=total,
                    payload_bytes=length, truncated=bool(truncated))


def stage(drive, rom, stage_bit=True, bit=None):
    app = drive / 'apps/gba'
    bit=bit or PROJECT/'build/gba.bit'
    artifacts = dict(gba_bit=bit, bios=PROJECT/'build/roms/open_bios.bin',
                     rom=PROJECT/'build/roms'/rom)
    for file in artifacts.values():
        if not file.exists():
            raise FileNotFoundError('Build artifact missing: ' + str(file))
    if not (drive / 'code.py').exists():
        raise RuntimeError('Drive does not contain a CircuitPython code.py')
    app.mkdir(parents=True, exist_ok=True)
    for source in (PROJECT / 'badge').glob('*.py'):
        shutil.copy2(source, app/source.name)
    if stage_bit:
        shutil.copy2(bit, app/'gba.bit')
    for name in ('open_bios.bin', 'BIOS_SOURCE.txt', 'BIOS_LICENSE.txt', rom):
        shutil.copy2(PROJECT/'build/roms'/name, app/name)
    if rom=='bld_demo.gba':
        for name in ('BLD_DEMO_LICENSE.txt','BLD_DEMO_SOURCE.txt'):
            shutil.copy2(PROJECT/'build/roms'/name,app/name)


def preflight(console, log):
    status = console.status()
    if not status['ram_ready'] or not status['panel_ready'] or status['ram_fault']:
        raise RuntimeError('Board preflight failed: ' + repr(status))
    print('BOARD_READY', status, flush=True)
    log['initial_status'] = status
    source = "_gba_host.reset()\n"
    for address in (0, 0x3fffc, 0x40000, 0x48000, 0x60000, 0x80000, 0x100000, 0x10fffc, 0x400000, 0x7ffffc):
        value = (address ^ 0xa55a6789) & 0xffffffff
        source += ("_gba_host.write(%d,struct.pack('<I',%d))\n" % (address, value))
    for address in (0, 0x3fffc, 0x40000, 0x48000, 0x60000, 0x80000, 0x100000, 0x10fffc, 0x400000, 0x7ffffc):
        value = (address ^ 0xa55a6789) & 0xffffffff
        source += "assert _gba_host.read(%d,4)==struct.pack('<I',%d), 'PSRAM alias/readback'\n" % (address, value)
    source += "print('PSRAM_BOUNDARY_TEST_PASS')\n"
    result = console.execute(source)
    if 'PSRAM_BOUNDARY_TEST_PASS' not in result:
        raise RuntimeError('PSRAM test did not complete')
    log['psram_boundary_test'] = 'pass'
    print(result.strip(), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', default='COM9')
    parser.add_argument('--drive', type=Path, default=Path('E:/'))
    parser.add_argument('action', choices=['diagnostic', 'suite', 'demo', 'status'])
    parser.add_argument('--bit',type=Path,default=PROJECT/'build/gba.bit',
                        help='Use a separately built FPGA candidate without replacing build/gba.bit')
    parser.add_argument('--minutes', type=float, default=60)
    parser.add_argument('--retry-stalled-boot', action='store_true',
                        help='Log and retry a stalled BIOS boot up to twice (bring-up only)')
    parser.add_argument('--temporary-rom', action='store_true',
                        help='Reuse GBA bitstream disk space to flash the test ROM, then restore the bitstream')
    parser.add_argument('--resume', action='store_true',
                        help='Collect the already-running guest without uploading or resetting it')
    args = parser.parse_args()
    console = Console(args.port)
    if args.action == 'status':
        console.connect()
        print(json.dumps(console.status(), indent=2))
        console.execute('_gba_spi.deinit()\n')
        console.close()
        return
    # Stop CircuitPython autoreload before USB filesystem writes.
    console.execute('import supervisor\nsupervisor.runtime.autoreload=False\n')
    rom = {'diagnostic':'diagnostic.gba','suite':'suite-bench.gba','demo':'bld_demo.gba'}[args.action]
    log = dict(test=args.action, rom=rom, started=time.strftime('%Y-%m-%dT%H:%M:%S%z'))
    out = PROJECT/'build/hardware'
    out.mkdir(parents=True, exist_ok=True)
    device_bit = args.drive/'apps/gba/gba.bit'
    temporary_stage = False
    try:
        log['rom_file_sha256']=hashlib.sha256((PROJECT/'build/roms'/rom).read_bytes()).hexdigest()
        log['bit_file_sha256']=hashlib.sha256(args.bit.read_bytes()).hexdigest()
        log['bios_file_sha256']=hashlib.sha256((PROJECT/'build/roms/open_bios.bin').read_bytes()).hexdigest()
        if not args.resume and device_bit.is_file():
            previous=device_bit.read_bytes()
            previous_hash=hashlib.sha256(previous).hexdigest()
            backup=out/('device-before-'+args.action+'-'+previous_hash[:12]+'.bit')
            backup.write_bytes(previous)
            if backup.read_bytes()!=previous:
                raise RuntimeError('Device bitstream backup verification failed')
            log['previous_device_bit_sha256']=previous_hash
            log['previous_device_bit_backup']=str(backup)
        if args.temporary_rom and not args.resume:
            # Only replace this runner's GBA artifact; retain a local backup
            # before freeing its space on the small CircuitPython volume.
            if not args.bit.is_file():
                raise FileNotFoundError('Build artifact missing: '+str(args.bit))
            if device_bit.exists():
                backup = out/'device-before-temporary-gba.bit'
                shutil.copy2(device_bit, backup)
                if backup.read_bytes() != device_bit.read_bytes():
                    raise RuntimeError('Device bitstream backup verification failed')
                device_bit.unlink()
            temporary_stage = True
        size = (PROJECT/'build/roms'/rom).stat().st_size
        if args.resume:
            console.connect()
            status = console.status()
            if not status['run'] or not status['ram_ready'] or status['ram_fault']:
                raise RuntimeError('No running GBA guest to resume: ' + repr(status))
            if status['pause']:
                console.execute('_gba_host.resume()\n')
            log['resumed_run'] = True
            log['initial_status'] = status
        else:
            stage(args.drive, rom, stage_bit=not args.temporary_rom, bit=args.bit)
            if not args.temporary_rom:
                console.upload()
            console.execute("import sys\nsys.path.insert(0,'/apps/gba')\n"
                            "from gba_app import install_rom\ninstall_rom('/apps/gba/%s')\n" % rom, timeout=180)
            if args.temporary_rom:
                (args.drive/'apps/gba'/rom).unlink()
                shutil.copy2(args.bit, device_bit)
                temporary_stage = False
                log['temporary_rom_staging'] = 'restored'
            console.upload()
            console.connect()
            preflight(console, log)
            result = console.execute("print('GBA_START',_gba_host.start(%d))\n" % size, timeout=180)
            print(result.strip(), flush=True)
        manifest = None
        if args.action == 'suite':
            metadata = (PROJECT/'build/roms/SUITE_SOURCE.txt').read_text()
            actual_hash = hashlib.sha256((PROJECT/'build/roms'/rom).read_bytes()).hexdigest()
            if actual_hash == SUITE_PROGRESS_ROM_SHA256 and 'ROM SHA256: ' + actual_hash in metadata:
                manifest = json.loads((PROJECT/'vendor/openfpga-GBA/benchmarks/mgba-suite/test-manifest.json').read_text())['suites']
        deadline = time.monotonic() + args.minutes*60
        boot_complete = False
        boot_sample = None
        stalled_polls = 0
        log['boot_restarts'] = 0
        while time.monotonic() < deadline:
            status = console.status()
            log['last_status'] = status
            print('GBA_STATUS', status, flush=True)
            if status['ram_fault'] or status['overflow'] or status['error']:
                raise RuntimeError('Hardware fault: ' + repr(status))
            # Observe BIOS startup through status; guest reports do not exist
            # yet and reading them would unnecessarily pause initialization.
            boot_complete |= 0x02000000 <= status['pc'] < 0x0e000000
            if not boot_complete:
                sample = (status['pc'], status['frames'])
                stalled_polls = stalled_polls + 1 if sample == boot_sample and status['ram_idle'] else 0
                boot_sample = sample
                if args.retry_stalled_boot and stalled_polls >= 10:
                    if log['boot_restarts'] >= 2:
                        raise RuntimeError('BIOS startup stalled after two logged warm restarts')
                    log['boot_restarts'] += 1
                    print('GBA_BIOS_STALL_RESTART', log['boot_restarts'], flush=True)
                    print(console.execute("print('GBA_RESTART',_gba_host.start(%d))\n" % size,
                                          timeout=180).strip(), flush=True)
                    boot_sample = None
                    stalled_polls = 0
                time.sleep(5)
                continue
            if args.action == 'demo':
                from check_bld_demo import check_demo
                check_demo(console,log,out)
                log['result']='demo_checks_pass'
                print('GBA_BLD_DEMO_CHECKS_PASS',log['demo'],flush=True)
                return
            report = console.save(0, 64 if args.action == 'diagnostic' else 32)
            log['last_report_hex'] = report.hex()
            if manifest is not None:
                progress = console.suite_progress()
                if progress['available'] and progress['suite'] < len(manifest):
                    suite = manifest[progress['suite']]
                    progress['suite_name'] = suite['name']
                    # ActiveInfo stores only eight bits of the test index.
                    # Larger suites cannot uniquely identify a case this way.
                    if len(suite['tests']) > 255:
                        progress['test_index_ambiguous'] = True
                    elif progress['test'] < len(suite['tests']):
                        progress['test_name'] = suite['tests'][progress['test']]
                log['suite_progress'] = progress
                (out/'suite-progress.json').write_text(json.dumps(progress, indent=2), encoding='utf-8')
                print('GBA_SUITE_PROGRESS', progress, flush=True)
            if args.action == 'diagnostic' and report[:8] == b'GBADIAG1':
                version, passed, done, keys, counter = struct.unpack_from('<5I', report, 8)
                arithmetic_error, shifter_error, banking_error = struct.unpack_from('<3I', report, 36)
                log['diagnostic'] = dict(version=version, passed=passed, done=done, keys=keys,
                                         counter=counter, arithmetic_error=arithmetic_error,
                                         shifter_error=shifter_error, banking_error=banking_error)
                if done == 0x600d600d:
                    if passed != 2047:
                        raise RuntimeError('Diagnostic checks failed: ' + repr(log['diagnostic']))
                    for mask in (1,2,4,8,16,32,64,128,256,512,0x300,0):
                        console.execute('_gba_host.keys(%d)\n' % mask)
                        key_deadline = time.monotonic() + 10
                        while time.monotonic() < key_deadline:
                            observed = struct.unpack_from('<I', console.save(20,4))[0]
                            if observed == mask:
                                break
                            time.sleep(0.1)
                        else:
                            raise RuntimeError('KEYINPUT readback mismatch %x vs %x' % (observed,mask))
                    console.execute('_gba_host.keys(None)\n')
                    log['key_injection'] = 'pass'
                    log['result'] = 'pass'
                    print('GBA_DIAGNOSTIC_PASS', log['diagnostic'], flush=True)
                    return
            if args.action == 'suite' and report[:12].rstrip(b'\0') == b'GBA_BENCH_V1':
                length, crc, flags, offset = struct.unpack_from('<4I', report, 16)
                if not flags and offset == 32 and 0 < length <= 65504:
                    save = console.save(0, offset+length)
                    (out/'suite-bench.sav').write_bytes(save + bytes(65536-len(save)))
                    import subprocess
                    script = PROJECT/'vendor/openfpga-GBA/scripts/parse_mgba_bench_save.py'
                    parsed = subprocess.run(
                        [sys.executable, str(script), str(out/'suite-bench.sav'), '--json'],
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
                    (out/'suite-results.json').write_text(parsed.stdout, encoding='utf-8')
                    if parsed.returncode == 0:
                        log['result'] = 'report_complete'
                        print(parsed.stdout, flush=True)
                        return
                    log['parser_error'] = parsed.stderr
            time.sleep(5)
        raise RuntimeError('ROM test did not complete before the timeout')
    except serial.SerialException as exc:
        log['result'] = 'interrupted'
        log['error'] = str(exc)
        raise
    except Exception as exc:
        log['result'] = 'failed'
        log['error'] = str(exc)
        raise
    finally:
        if temporary_stage:
            staged_rom = args.drive/'apps/gba'/rom
            if staged_rom.exists():
                staged_rom.unlink()
            shutil.copy2(args.bit, device_bit)
        (out/(args.action+'.json')).write_text(json.dumps(log, indent=2), encoding='utf-8')
        try:
            console.execute('_gba_spi.deinit()\n')
        except Exception:
            pass
        console.close()


if __name__ == '__main__':
    main()
