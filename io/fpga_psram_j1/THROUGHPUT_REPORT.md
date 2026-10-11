# Hardware-tested burst SPI

The GreyMecha now runs one-bit SPI bursts at approximately 51.36 MHz SCK,
with **4.85 MB/s writes and 4.63 MB/s reads** measured inside the FPGA.
This is approximately 17x/16x the original single-byte design. The complete
8 MiB write/verify test passed on the connected COM9 badge on 2026-10-12,
as did an unaligned burst crossing a 1 KiB page boundary.

The APS6404L has no two-bit dual-SPI command. This build uses one-bit
`02` writes and one-bit `0B` fast reads with eight dummy clocks. Quad mode
remains disabled because the separate QPI hardware tests fail; see
[EXPERIMENTS.md](EXPERIMENTS.md).

| Configuration | Measured SCK | Burst | Write MB/s | Read MB/s |
| --- | ---: | ---: | ---: | ---: |
| Original SPI with benchmark counters | 12.85 MHz | 1 byte | 0.284 | 0.284 |
| SPI bursts, `03` reads | 12.84 MHz | 8 bytes | 1.020 | 1.020 |
| Fast SPI bursts, `0B` reads | 51.36 MHz | 16 bytes | 4.849 | 4.630 |

MB/s uses decimal megabytes. An autonomous 64 KiB phase takes 1,388,544
write cycles or 1,454,080 read/verify cycles in the fast build. The counters
include command, address, dummy clocks, CE spacing and controller/verification
overhead, and exclude host USB traffic. Native RP2350 PulseIn capture of
the system-clock/65536 reference on GP12 calibrates the rate. Three clock
samples for the fast benchmark were 102.726, 102.730 and 102.735 MHz.

The full test used a separate 102.704 MHz calibration, reporting 4.847 MB/s
writes and 4.629 MB/s reads. It wrote and verified 128 consecutive 64 KiB
regions, with eight pattern seeds distributed across the regions. It is a
pattern test of every byte, not exhaustive testing of every possible value
and operating condition. The unaligned test starts at `0x3f9`.

Evidence:

- [8-byte burst benchmark](validation/spi_burst_12mhz.log)
- [Fast benchmark, byte/data/address tests and reset recovery](validation/spi_burst_51mhz.log)
- [Full 8 MiB and unaligned page-crossing test](validation/spi_burst_full_8mib.log)

## Tested artifact

| Item | Result |
| --- | --- |
| Bitstream | [bitstreams/spi_burst_51mhz.bit](bitstreams/spi_burst_51mhz.bit) |
| Size | 126,567 bytes, compressed |
| Parameters | QPI=0, SPI_BURST=1, SPI_FAST_READ=1, OSC_DIV=3, HALF_PERIOD=1, BURST_BYTES=16, TRACE=0 |
| Nominal system/SCK clocks | 103.33 / 51.67 MHz |
| Final routed internal maximum frequency | 114.42 MHz, PASS at 103.34 MHz |
| Pre-pack LUT4s, including carry | 1,676 / 24,288 |
| Flip-flops | 770 / 24,288 |
| Block RAM / DSP usage | 0 / 0 |
| Regression | Eight protocol/wiring simulations passed |
| Strict lint | Four configurations passed |
| Synthesis | `check -assert` and board-pin check passed |
| Connected hardware | ID `0d 5d 53`; byte/address/data tests, five 256-byte regions, eight 64 KiB benchmarks, reset recovery, full 8 MiB and page crossing passed |

SHA256:

```text
c0860d3a59485270b2f0ae77b15de0e2995f9daeb9416dccfcd65413b145b687
```

Sixteen-byte transfers keep CE# selected for approximately 3.2 us writes or
3.4 us reads on this board, under the 8 us limit. Init/reset/ID retain a
slower serial clock. Internal nextpnr timing and observed hardware success
do not establish external I/O timing margin over temperature or oscillator
tolerance. These are measurements of this connected setup.

## Build and use

The Makefile defaults now select the fast serial build. To reproduce in a
new build directory:

```sh
make test lint
make all BUILD=build/spi_fast_rebuild QPI=0 SPI_BURST=1 SPI_FAST_READ=1 OSC_DIV=3 HALF_PERIOD=1 BURST_BYTES=16
```

Copy the tested bitstream to `/apps/psram_j1/fpga_psram_j1.bit` and copy
`badge/psram.py` and `badge/run.py` alongside it. The current badge already
has this bitstream loaded through volatile FPGA configuration. Its root
`code.py` was preserved.

```python
import sys
sys.path.append('/apps/psram_j1')
import psram
psram.load()
p = psram.Psram()
print(p.benchmark(clock_hz=p.measure_clock()))  # Destructively tests 64 KiB.
p.deinit()
```

Client `read()` and `write()` still send one host command per byte, so they
remain limited by the slow CircuitPython command bridge. FPGA logic can
reuse `spi_burst.v` directly: provide 1..128 bytes, feed the prefetched
`tx_index`/`tx_data` interface, and consume `rx_valid`/`rx_index`/`rx_data`.
Supply bytes without stalls and choose a burst length that respects the
CE# duration limit. The demo's autonomous tests exercise this interface.

The original baseline bitstream remains in `bitstreams/spi_12mhz.bit`,
with its original report in [BUILD_REPORT.md](BUILD_REPORT.md).
