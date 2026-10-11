import sys
import supervisor
supervisor.runtime.autoreload = False
sys.path.append('/apps/psram_j1')
import psram
psram.load()
p = psram.Psram()
try:
    print('ID:', list(p.id()))
    before = p.pins()
    print('PINS_BEFORE:', before)
    print('READ:', list(p.read(0x100)))
    after = p.pins()
    print('PINS_AFTER:', after)
    print('READ_CLOCK_EDGES:', after['clock_edges'] - before['clock_edges'])
    print('RESET_ID:', list(p.id(reset=True)))
    print('PINS_AFTER_RESET:', p.pins())
finally:
    p.deinit()
