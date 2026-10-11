import time
import sys
sys.path.append('/apps/psram_j1')
import psram
import digitalio
psram.load()
spi = psram.BitBangSpi()
try:
    spi.miso.switch_to_input(pull=digitalio.Pull.UP)
    print("IDLE_MISO:", spi.miso.value)
    spi.cs.value = False
    time.sleep(0.01)
    print("SELECTED_MISO:", spi.miso.value)
    bits = []
    for n in range(16):
        spi.sck.value = True
        time.sleep(0.001)
        bits.append(int(spi.miso.value))
        spi.sck.value = False
        time.sleep(0.001)
    spi.cs.value = True
    print("SLOW_MISO_BITS:", bits)
    print("RAW_REPLY:", list(spi.transfer(bytes(8))))
finally:
    spi.deinit()
