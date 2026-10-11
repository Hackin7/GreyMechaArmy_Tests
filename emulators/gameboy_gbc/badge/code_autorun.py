"""Deferred FPGA loader that immediately starts the Game Boy BRAM host.

Install as CIRCUITPY ``code.py`` only for automated bring-up.  It performs
the FPGA upload before creating any display objects, then lets CircuitPython
complete the comparatively slow bit-banged ROM transfer without a desktop
serial session being held open.
"""

import microcontroller


nvm = microcontroller.nvm
if nvm[0] == 0xAA:
    length = nvm[1]
    bitstream = bytes(nvm[2:2 + length]).decode("utf-8")
    nvm[0:2] = b"\x00\x00"

    import displayio
    displayio.release_displays()
    import hardware.fpga
    hardware.fpga.upload_bitstream(bitstream)

    import sys
    sys.path.append("/apps/gameboy_gbc")
    import main
    main.app(cache_mode=False, upload_bitstream=False)

# Remain safely idle unless a deferred image was explicitly selected.
while True:
    pass
