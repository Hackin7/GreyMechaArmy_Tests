import sys
sys.path.append('/apps/psram_j1')
import psram
psram.load()
p = psram.Psram()
try:
    print('MODE:', p.status())
    for value in (0, 0x11, 0x22, 0x44, 0x88, 0x55, 0xaa, 0xff):
        p.write(0x100, bytes((value,)))
        print('WRITE_READ:', hex(value), list(p.read(0x100)))
    print('PINS:', p.pins())
finally:
    p.deinit()
