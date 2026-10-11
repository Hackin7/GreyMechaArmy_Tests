# Nominal 16 MHz flash SPI backend

## Clocking

The existing PLL has CLKOP_DIV=8 (panel) and CLKOS_DIV=40 (core),
so panel/core is 5:1, not the 4:1 implied by the old panel constraint.
CLKOS2_DIV=10 adds a separate flash clock at four times the core rate.
Constraints now target 16 MHz core, 80 MHz panel and 64 MHz flash. The
internal oscillator remains the source; these are nominal target rates,
not a measurement or guarantee of physical oscillator frequency.

In fast mode, each SPI bit has four fast-clock cycles: raise SCK, sample
MISO while high, lower SCK/update MOSI, then hold low. At nominal 64 MHz
this yields a 62.5 ns bit period, 31.25 ns high/low widths, and 31.25 ns
MOSI setup for subsequent bits. MISO is sampled three fast-clock cycles
(46.875 ns) after the preceding falling SCK edge. First-bit MOSI/CS setup
is one fast-clock cycle. The command remains 0x0B with 24-bit physical
address and eight dummy clocks, followed by 256 bytes.

## Clock-domain crossings

- The core captures the aligned cartridge address, pulses fill_begin and
  toggles the request bit. It holds the address until completion.
- Two fast-domain synchronizer stages expose the request toggle; only then
  is the stable bundled address captured and the reader started.
- An eight-entry FIFO carries {byte offset, byte data} from fast to core.
  Gray pointers cross two-stage synchronizers; data is stored in distributed
  RAM and is exposed only after the write pointer has synchronized.
- FIFO fullness backpressures the reader between bytes, with SCK low.
- The core drains the FIFO and writes the existing cache. Completion is
  generated one cycle after presenting byte 255, so the last cache write
  precedes tag validity. Completion releases the active request; holding
  start high cannot launch it twice.
- Fast reset asserts asynchronously and deasserts synchronously. Core reset,
  including the host reset pulse, resets the request state and both FIFO
  sides, discarding an interrupted line without committing it.

The fallback uses the original core-clocked, three-cycle SPI reader, without
the CDC/FIFO path. Build with FLASH_SPI_FAST=0. ROM layout, the 16 KiB cache,
Game Boy memories, panel colour correction and launcher protocol are unchanged.

## Verification

`make sim-flash-matrix` tests the FIFO under randomized full/empty pressure
(4,000 ordered records across resets), slow mode, fast mode with 8 KiB cache,
and fast mode with 16 KiB cache. The clocks have an intentional phase offset.
The flash model adds output propagation delay. Assertions cover SCK period
and duty cycle, MOSI setup, command/address/dummy length, all 256 byte values
and offsets, no early commit, cache hits, bank boundaries, highest supported
ROM address and reset/restart during an active transaction.

The flash model uses 12 ns output propagation delay. An additional test slows
the cache clock to 1 MHz while leaving the reader at 64 MHz, forcing the FIFO
to fill. All bytes still arrive correctly; only SCK low intervals stretch.
Those deliberately throttled fills measure 262 us, as expected for the slower
consumer, rather than the normal 130.75 us.

Measured core-domain fill_begin-to-fill_commit latency is 130.75 us in fast
mode and 391.5 us in fallback mode. Cache lookup/retry and request startup
add a small amount beyond this measurement. This is fill latency, not a
claim of a threefold whole-game speedup.

The full Defcon test uses the backend and flash-pin model, uploads only the
header, runs 480 frames and presses Start at frame 360 (release at 370).
The acceptance criteria are zero ROM-byte mismatches and an unchanged final
frame compared with the prior 16 KiB-cache run. Build with `make bit-flash`;
check all three clock targets, BRAM <=56 and clock-domain timing reports.

The completed fast-backend Defcon run passed all 480 frames, with zero ROM
byte mismatches and 7,327 misses. Start was pressed at frame 360 and released
at frame 370. Its final PPM is byte-for-byte identical to the prior slow
backend's 16 KiB-cache capture; miss counts are unchanged, as expected.

The current routed fast build uses 55/56 DP16KD blocks. Reported maximum
frequencies are 24.42 MHz core (16 MHz target), 101.78 MHz panel (80 MHz target)
and 185.67 MHz flash domain (64 MHz target). The reported cross-domain paths
were inspected, including the Gray-pointer crossing and reset synchronizer.
The MISO input-to-register path is reported as 2.00 ns; this is an internal
routing figure, not a complete external flash timing budget.

## External timing limitation

Internal place-and-route timing and an SPI behavioral model do not prove
board-level flash timing. The tests check nominal output pulse/setup timing;
they cannot include the exact pad/USRMCLK routing skew, board trace delay,
flash part/voltage/temperature corners or oscillator tolerance. In particular,
MISO is SPI-source-synchronous data, not a signal that should be passed through
a generic two-flop synchronizer. Hardware validation remains required before
calling this backend board-proven. No automatic flash programming or board
upload is performed by these build/test commands.
