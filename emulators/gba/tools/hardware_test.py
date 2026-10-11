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
import json
import shutil
import struct
import sys
import time
from pathlib import Path
import serial

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT.parents[1] / 'io/fpga_psram_j1/scripts'))
from repl_run import read_until


class Console:
    def __init__(self, port):
        self.port = port

    def execute(self, source, timeout=120, resets=False):
        with serial.Serial(self.port, 115200, timeout=0.1) as console:
            console.write(b'\r\x03\x03')
            time.sleep(0.3)
            console.write(b'\x02\r\x03')
            time.sleep(0.3)
            console.reset_input_buffer()
            console.write(b'\x01')
            read_until(console, b'raw REPL; CTRL-B to exit\r\n>', 5)
            encoded = source.encode()
            for offset in range(0, len(encoded), 128):
                console.write(encoded[offset:offset + 128])
                time.sleep(0.003)
            console.write(b'\x04')
            read_until(console, b'OK', 5)
            if resets:
                return ''
            stdout = read_until(console, b'\x04', timeout)[:-1]
            stderr = read_until(console, b'\x04', 5)[:-1]
            read_until(console, b'>', 5)
            console.write(b'\x02')
        if stderr:
            raise RuntimeError(stderr.decode('utf-8', 'replace'))
        return stdout.decode('utf-8', 'replace')

    def upload(self):
        self.execute("import sys\nsys.path.insert(0,'/apps/gba')\n"
                     "from gba_app import deferred_upload\ndeferred_upload()\n", resets=True)
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            time.sleep(1)
            try:
                output = self.execute("print('GBA_BOOT_REPL_READY')\n", timeout=5)
                if 'GBA_BOOT_REPL_READY' in output:
                    return
            except (serial.SerialException, OSError, RuntimeError):
                continue
        raise RuntimeError('Badge did not reconnect after bitstream upload')

    def connect(self):
        self.execute("import sys\nsys.path.insert(0,'/apps/gba')\n"
                     "from gba_app import GBAHost, BitBangSpi\n"
                     "import json, time, struct, binascii\n"
                     "_gba_spi=BitBangSpi()\n_gba_host=GBAHost(_gba_spi)\n")

    def status(self):
        return json.loads(self.execute("print(json.dumps(_gba_host.status()))\n").strip())

    def save(self, address, size):
        result = self.execute("_gba_host.pause()\n"
                              "print(binascii.hexlify(_gba_host.read(%d,%d,save=True)).decode())\n"
                              "_gba_host.resume()\n" % (address, size), timeout=180)
        return bytes.fromhex(result.strip())


def stage(drive, rom):
    app = drive / 'apps/gba'
    artifacts = dict(gba_bit=PROJECT/'build/gba.bit', bios=PROJECT/'build/roms/open_bios.bin',
                     rom=PROJECT/'build/roms'/rom)
    for file in artifacts.values():
        if not file.exists():
            raise FileNotFoundError('Build artifact missing: ' + str(file))
    if not (drive / 'code.py').exists():
        raise RuntimeError('Drive does not contain a CircuitPython code.py')
    app.mkdir(parents=True, exist_ok=True)
    for source in (PROJECT / 'badge').glob('*.py'):
        shutil.copy2(source, app/source.name)
    for name in ('gba.bit',):
        shutil.copy2(PROJECT/'build'/name, app/name)
    for name in ('open_bios.bin', 'BIOS_SOURCE.txt', 'BIOS_LICENSE.txt', rom):
        shutil.copy2(PROJECT/'build/roms'/name, app/name)


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
    parser.add_argument('action', choices=['diagnostic', 'suite', 'status'])
    parser.add_argument('--minutes', type=float, default=60)
    args = parser.parse_args()
    console = Console(args.port)
    if args.action == 'status':
        console.connect()
        print(json.dumps(console.status(), indent=2))
        console.execute('_gba_spi.deinit()\n')
        return
    # Stop CircuitPython autoreload before USB filesystem writes.
    console.execute('import supervisor\nsupervisor.runtime.autoreload=False\n')
    rom = 'diagnostic.gba' if args.action == 'diagnostic' else 'suite-bench.gba'
    stage(args.drive, rom)
    log = dict(test=args.action, rom=rom, started=time.strftime('%Y-%m-%dT%H:%M:%S%z'))
    out = PROJECT/'build/hardware'
    out.mkdir(parents=True, exist_ok=True)
    try:
        console.upload()
        console.execute("import sys\nsys.path.insert(0,'/apps/gba')\n"
                        "from gba_app import install_rom\ninstall_rom('/apps/gba/%s')\n" % rom, timeout=180)
        console.upload()
        console.connect()
        preflight(console, log)
        size = (PROJECT/'build/roms'/rom).stat().st_size
        result = console.execute("print('GBA_START',_gba_host.start(%d))\n" % size, timeout=180)
        print(result.strip(), flush=True)
        deadline = time.monotonic() + args.minutes*60
        while time.monotonic() < deadline:
            status = console.status()
            log['last_status'] = status
            print('GBA_STATUS', status, flush=True)
            if status['ram_fault'] or status['overflow'] or status['error']:
                raise RuntimeError('Hardware fault: ' + repr(status))
            report = console.save(0, 64 if args.action == 'diagnostic' else 32)
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
                        time.sleep(0.5)
                        observed = struct.unpack_from('<I', console.save(20,4))[0]
                        if observed != mask:
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
                    parsed = subprocess.run([sys.executable, str(script), str(out/'suite-bench.sav'), '--json'], capture_output=True, text=True)
                    (out/'suite-results.json').write_text(parsed.stdout, encoding='utf-8')
                    if parsed.returncode == 0:
                        log['result'] = 'report_complete'
                        print(parsed.stdout, flush=True)
                        return
                    log['parser_error'] = parsed.stderr
            time.sleep(5)
        raise RuntimeError('ROM test did not complete before the timeout')
    except Exception as exc:
        log['result'] = 'failed'
        log['error'] = str(exc)
        raise
    finally:
        (out/(args.action+'.json')).write_text(json.dumps(log, indent=2), encoding='utf-8')
        try:
            console.execute('_gba_spi.deinit()\n')
        except Exception:
            pass


if __name__ == '__main__':
    main()
