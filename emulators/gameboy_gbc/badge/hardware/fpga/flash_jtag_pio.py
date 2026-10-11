# Persistent JTAG DR-scan PIO program for ECP5 SPI-flash access.
#
# Entry and exit TAP state: Select-DR-Scan. A 32-bit header contains the
# number of data bits minus one. TMS is asserted only for the final data bit,
# then the program clocks Exit1-DR -> Pause-DR -> Exit2-DR -> Update-DR ->
# Select-DR-Scan and stalls with TCK low waiting for the next header.
#
# The count-driven transport structure is adapted from pico-dirtyJtag's
# MIT-licensed jtag.pio.

import adafruit_pioasm


PIO_SOURCE = r"""
.program flash_jtag_dr
.side_set 1 opt
.wrap_target
    pull block          side 0
    out x, 32           side 0

    ; Select-DR-Scan -> Capture-DR -> Shift-DR.
    set pins, 0         side 0
    nop                 side 1
    nop                 side 0
    nop                 side 1

bitloop:
    out pins, 1         side 0
    jmp x-- normal      side 0

    ; Final data bit: assert TMS before its rising edge.
    set pins, 1         side 0
    nop                 side 1
    in pins, 1          side 1
    jmp finish          side 0

normal:
    nop                 side 1
    in pins, 1          side 1
    jmp bitloop         side 0

finish:
    ; Exit1-DR -> Pause-DR -> Exit2-DR -> Update-DR -> Select-DR-Scan.
    set pins, 0         side 0
    nop                 side 1
    set pins, 1         side 0
    nop                 side 1
    nop                 side 0
    nop                 side 1
    nop                 side 0
    nop                 side 1
    nop                 side 0
    ; Completion byte: emitted only after TAP exit and TCK-low are complete.
    in null, 8          side 0
.wrap
"""

PROGRAM = adafruit_pioasm.Program(PIO_SOURCE)
