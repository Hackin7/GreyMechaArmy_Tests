"""Read FPGA configuration status and shared panel pins without reprogramming."""
import board
import digitalio
import microcontroller
import binascii
import struct
import supervisor
import sys
import os
supervisor.runtime.autoreload = False
print('BADGE', board.board_id, binascii.hexlify(microcontroller.cpu.uid).decode())
print('MAIN_INITIALIZED', 'hardware.main' in sys.modules)
print('LOADER_MARKER', microcontroller.nvm[0])
try:
    print('CAMERA_BITSTREAM_SIZE', os.stat('/fpga/app_bitstreams/fpga_ov7670.bit')[6])
except OSError as e:
    print('CAMERA_BITSTREAM_FILE', repr(e))
from hardware.fpga import jtag
jtag.bitbang_tms_on()
jtag.bitbang_jtag_on()
try:
    jtag.reset_tap()
    jtag.runtest_idle(1, 0)
    jtag.sir_idle(b'\x3c', 2, 1)  # LSC_READ_STATUS, no erase/program commands
    response = bytearray(4)
    jtag.sdr_response(response)
    status = struct.unpack('<I', response)[0]
    print('FPGA_STATUS', hex(status), 'DONE', bool(status & 0x100), 'FAIL', bool(status & 0x2000))
finally:
    jtag.reset_tap()
    jtag.bitbang_jtag_input()
    jtag.bitbang_jtag_off()
    jtag.bitbang_tms_off()
for label,pin in [('SCLK',board.GP2),('MOSI',board.GP3),('DC',board.GP4),('CS',board.GP5),('RESET',board.GP6)]:
    try:
        p = digitalio.DigitalInOut(pin)
        try:
            p.switch_to_input()
            ones = sum(int(p.value) for _ in range(512))
            print('PANEL_PIN', label, ones, '/512 high')
        finally:
            p.deinit()
    except Exception as e:
        print('PANEL_PIN',label,repr(e))
