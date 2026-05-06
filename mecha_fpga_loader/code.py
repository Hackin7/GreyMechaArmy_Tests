import gc

# === mecha_fpga_loader: deferred bitstream load ===========================
# bitstream_loader.bitstream_loader() persists the chosen .bit path in
# microcontroller.nvm (NOT on the filesystem — the FS is read-only from
# Python while USB is connected) and calls supervisor.reload(). On the
# next boot we run that upload BEFORE any display/hardware init, so it
# executes in the same fresh post-supervisor state that
# /hackin7/picorv32_test_spi/run.py runs in at the REPL.
# Critical: nothing here may import `hardware.main` (which would re-create
# the OLED display+busio.SPI and put us right back in the broken state).
#
# NVM layout matches apps/bitstream_loader.py:
#   nvm[0]            = 0xAA when a load is pending, anything else = none
#   nvm[1]            = length L of the UTF-8 path
#   nvm[2:2+L]        = path bytes
import microcontroller
_nvm = microcontroller.nvm
if _nvm[0] == 0xAA:
    _len = _nvm[1]
    _pending_bit = bytes(_nvm[2:2 + _len]).decode("utf-8")
    # Clear the marker so the next normal reset returns to the menu.
    _nvm[0:2] = b"\x00\x00"

    import displayio
    displayio.release_displays()  # in case the display survived soft reset
    import hardware.fpga
    _h = hardware.fpga.upload_bitstream(_pending_bit)
    # Idle forever; user resets the badge to return to the menu.
    import time
    while True:
        time.sleep(1)
# === end deferred bitstream load ==========================================

try:
    import hackin7.lake_bomb_defuse_device.pin_entry_app
except Exception as e:
    print(e)

import hardware.main as hardware
import apps

gc.enable()

### Initialisation ####################################
hw_state = hardware.hw_state
apps.display_fpga_loading_menu(hw_state)
hw_state["fpga_overlay"].init() 

### Menu ############################################
apps.menu(hw_state)
