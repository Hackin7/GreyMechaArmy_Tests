import gc
import time
import board
import digitalio
import hardware.fpga
gc.collect()

pins = [digitalio.DigitalInOut(pin) for pin in (
    board.GP8, board.GP9, board.GP10, board.GP11,
    board.GP12, board.GP13, board.GP14, board.GP15)]
for pin in pins:
    pin.switch_to_input()
try:
    h = hardware.fpga.upload_bitstream("/hardware/fpga/test_bitstreams/probe.bit")
    h.deinit()
    for n in range(4):
        time.sleep(0.25)
        value = sum((1 << index) for index, pin in enumerate(pins) if pin.value)
        print("PROBE_INTERCONNECT:", hex(value))
finally:
    for pin in pins:
        pin.deinit()
