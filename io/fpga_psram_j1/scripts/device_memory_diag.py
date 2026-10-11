"""Read-only chip identification and memory reads; no PSRAM writes."""
import sys
import supervisor
supervisor.runtime.autoreload = False
sys.path.append('/apps/psram_j1')
import psram
psram.load()
p = psram.Psram()
try:
    for attempt in range(3):
        print('RESET_ID:', list(p.id(reset=True)))
    for address in (0, 0x100, 0x400000, 0x7fffff):
        print('READ:', hex(address), list(p.read(address)))
    print('FINAL_STATUS:', p.status())
finally:
    p.deinit()
