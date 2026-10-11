import sys
sys.path.append('/apps/psram_j1')
import psram
psram.load('/apps/psram_j1/spi_baseline.bit')
p = psram.Psram()
p.write(0x200, b'\x03\x16\x29\x4c')
p.deinit()
psram.load()
p = psram.Psram()
try:
    print('READ:', list(p.read(0x200)))
    for index in range(31, -1, -1):
        r = p._command(9, value=index)
        word = (r['data'] << 24) | r['address']
        print('TRACE:', index, hex(word >> 16), hex(word & 65535))
finally:
    p.deinit()
