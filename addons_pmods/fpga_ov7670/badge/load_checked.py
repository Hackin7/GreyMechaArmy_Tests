"""Run with tools/run_device.ps1 -SoftReset, from a clean raw REPL."""
import os
import board
import digitalio
import displayio
import supervisor
import time
supervisor.runtime.autoreload = False
assert board.board_id == 'greybadge'
path='/fpga/app_bitstreams/fpga_ov7670.bit'
print('CAMERA_FILE',path,os.stat(path)[6])
displayio.release_displays()
import hardware.fpga
reset_pin=digitalio.DigitalInOut(board.GP20)
try:
    reset_pin.switch_to_output(value=False)
    time.sleep(0.1)
    reset_pin.value=True
    ok=hardware.fpga.ecp5p.prog(path)
    print('FPGA_PROGRAM_VERIFIED',ok)
    assert ok, 'FPGA configuration status failed'
finally:
    reset_pin.deinit()
time.sleep(2)
exec(open('/apps/ov7670/status.py').read())
