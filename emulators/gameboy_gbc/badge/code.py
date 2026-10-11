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


def _reset_to_launch(magic, path, status):
    import time
    encoded = path.encode("utf-8")
    if 2 + len(encoded) > len(_nvm):
        raise ValueError("Launch path is too long for NVM")
    status.message("Resetting for FPGA")
    time.sleep(0.3)
    status.release()
    # Leave enough time for the final black GC9A01 frame to reach the panel
    # before the MCU reset removes CircuitPython display ownership.
    time.sleep(0.1)
    _nvm[0:2] = bytes((magic, len(encoded)))
    _nvm[2:2 + len(encoded)] = encoded
    microcontroller.reset()


def _show_install_failure(status, error):
    _nvm[0:2] = b"\x00\x00"
    print("INSTALL_FAILED")
    try:
        import sys
        sys.print_exception(error)
    except AttributeError:
        import traceback
        traceback.print_exception(type(error), error, error.__traceback__)
    status.message("Error: " + str(error)[:28], error=True)
    import install_status
    install_status.wait_for_menu(status)


if _nvm[0] == 0xAB:
    # Run before hardware.main imports the display and FPGA overlay.  The
    # ECP5 flash programmer needs exclusive ownership of the JTAG pins.
    import supervisor
    supervisor.runtime.autoreload = False
    _len = _nvm[1]
    _rom_path = bytes(_nvm[2:2 + _len]).decode("utf-8")
    _nvm[0:2] = b"\x00\x00"

    import sys
    sys.path.append("/apps/gameboy_gbc")
    import main as gameboy
    import install_status
    _status = install_status.create("Game Boy")
    try:
        print("GB_INSTALL_BEGIN")
        _installed_size = gameboy.install_rom(
            _rom_path, progress=_status.callback, load_after=False)
        print("GB_INSTALL_DONE", _installed_size)
        # A real MCU reset releases every display, PIO, PWM, and GPIO owner.
        # The 0xAD handler below then loads the FPGA before hardware.main.
        _reset_to_launch(0xAD, _rom_path, _status)
    except Exception as _error:
        _show_install_failure(_status, _error)

if _nvm[0] == 0xAD:
    # Second-stage Game Boy launch after a real MCU reset. The marker carries
    # the current ROM path so launch does not depend on metadata writes.
    import supervisor
    supervisor.runtime.autoreload = False
    _len = _nvm[1]
    _rom_path = bytes(_nvm[2:2 + _len]).decode("utf-8")
    _nvm[0:2] = b"\x00\x00"

    import displayio
    displayio.release_displays()
    import hardware.fpga
    _h = hardware.fpga.upload_bitstream(
        "/apps/gameboy_gbc/gameboy_gbc_flash.bit")
    _h.deinit()

    import sys
    sys.path.append("/apps/gameboy_gbc")
    import main as gameboy
    gameboy.app(
        rom_path=_rom_path, flash_mode=True, upload_bitstream=False)

if _nvm[0] == 0xAA:
    # USB filesystem metadata writes must not interrupt a long-running FPGA
    # memory service after it has taken ownership of the panel and link pins.
    import supervisor
    supervisor.runtime.autoreload = False
    _len = _nvm[1]
    _pending_bit = bytes(_nvm[2:2 + _len]).decode("utf-8")
    # Clear the marker so the next normal reset returns to the menu.
    _nvm[0:2] = b"\x00\x00"

    import displayio
    displayio.release_displays()  # in case the display survived soft reset
    import hardware.fpga
    _h = hardware.fpga.upload_bitstream(_pending_bit)
    _h.deinit()

    if _pending_bit in (
            "/apps/gameboy_gbc/gameboy_gbc_bram.bit",
            "/apps/gameboy_gbc/gameboy_gbc_cache.bit",
            "/apps/gameboy_gbc/gameboy_gbc_flash.bit"):
        import sys
        sys.path.append("/apps/gameboy_gbc")
        import main as gameboy
        gameboy.app(cache_mode=_pending_bit.endswith("_cache.bit"),
                    flash_mode=_pending_bit.endswith("_flash.bit"),
                    upload_bitstream=False)

    # Idle forever; user resets the badge to return to the menu.
    import time
    while True:
        time.sleep(1)
# === end deferred bitstream load ==========================================

import hardware.main as hardware
import apps

gc.enable()

### Initialisation ####################################
hw_state = hardware.hw_state
apps.display_fpga_loading_menu(hw_state)
hw_state["fpga_overlay"].init()

### Menu ############################################
apps.menu(hw_state)
