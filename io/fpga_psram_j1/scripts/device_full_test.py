"""Destructive write/verify of all 8 MiB, in autonomous 64 KiB regions."""
import sys
import supervisor
supervisor.runtime.autoreload = False
sys.path.append('/apps/psram_j1')
import psram
psram.load()
p = psram.Psram()
try:
    assert p.status()['id_good']
    clock_hz = p.measure_clock(periods=1024)
    print('MEASURED_SYS_HZ:', clock_hz)
    print('MODE:', p.status())
    print('UNALIGNED_PAGE_CROSSING:', p.benchmark(0x3f9, seed=7, clock_hz=clock_hz))
    write_cycles = 0
    read_cycles = 0
    for block in range(128):
        result = p.benchmark(block * 65536, seed=block % 8, clock_hz=clock_hz)
        write_cycles += result['write_cycles']
        read_cycles += result['read_cycles']
        if block % 16 == 15:
            print('VERIFIED_BYTES:', (block + 1) * 65536)
    print('WRITE_MB_S:', 8388608 * clock_hz / (write_cycles * 1000000))
    print('READ_MB_S:', 8388608 * clock_hz / (read_cycles * 1000000))
    print('WRITE_CYCLES:', write_cycles, 'READ_CYCLES:', read_cycles)
    print('FINAL_STATUS:', p.status())
    print('FULL_8MIB_HARDWARE_PASS')
finally:
    p.deinit()
