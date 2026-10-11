"""Small destructive diagnostic, bypassing ID guard to isolate ID vs data."""
import sys
import supervisor
supervisor.runtime.autoreload = False
sys.path.append('/apps/psram_j1')
import psram
psram.load()
p = psram.Psram()
try:
    print('ID:', list(p.id()))
    success = True
    for value in (0x00, 0x55, 0xaa, 0xff):
        p.write(0x100, bytes((value,)))
        actual = p.read(0x100)[0]
        print('BYTE_DIAG: wrote', hex(value), 'read', hex(actual))
        success = success and actual == value
    print('BYTE_DIAG_PASS:', success)
finally:
    p.deinit()
