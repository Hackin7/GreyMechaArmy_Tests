# Shared PIO program for the JTAG bitstream burst.
#
# Side-set drives TCK; out pin drives TDI; in pin samples TDO. With autopull
# threshold=8 the host pushes bytes and the SM clocks 8 TDI bits per byte;
# autopush=8 means RX FIFO accumulates TDO response bytes (discarded by the
# caller during burst).
#
# The PIO clock/sample structure is adapted from pico-dirtyJtag's
# MIT-licensed jtag.pio. We diverge from dirtyJtag's count-word approach
# because CircuitPython's
# rp2pio.StateMachine.write puts each pushed byte into its own 32-bit FIFO
# entry (lower 8 bits, upper bits zero). dirtyJtag's PIO does an explicit
# `pull` + `out x, 32` to consume a 32-bit count, which would read garbage
# in the upper 24 bits if we tried it from CircuitPython. Instead, we drive
# a fixed inner loop that clocks exactly 8 bits per autopulled byte; the
# total bit count comes from len(buf) * 8, which is always byte-aligned for
# bitstream data.
#
# Per-byte cost: 1 cycle for `set x, 7` + 4 cycles × 8 bits = 33 SM cycles.
# Effective per-bit cost: 33 / 8 = 4.125 cycles/bit.

import adafruit_pioasm

PIO_SOURCE = r"""
.program jtag_burst
.side_set 1 opt
.wrap_target
    set x, 7        side 0
loop:
    out pins, 1     side 0
    nop             side 1
    in pins, 1      side 1
    jmp x-- loop    side 0
.wrap
"""

PROGRAM = adafruit_pioasm.Program(PIO_SOURCE)

# SM cycles per byte (averaged per-bit cost is 33/8 = 4.125).
CYCLES_PER_BYTE = 33
CYCLES_PER_BIT_NUM = 33  # numerator
CYCLES_PER_BIT_DEN = 8   # denominator
