# PSRAM throughput experiment status — 2026-10-12

The original working SPI demo is committed as `fcf34af`. Its preserved
bitstream is `bitstreams/spi_12mhz.bit`; see `BUILD_REPORT.md` for that artifact.
The subsequent throughput work produced a passing one-bit burst-SPI build,
now loaded on the badge; see [THROUGHPUT_REPORT.md](THROUGHPUT_REPORT.md).
The quad controller remains experimental and fails hardware validation.

## Passing SPI benchmark

An instrumented SPI build passed byte/string readback, data/address-line
checks, five 256-byte regions, eight autonomous 64 KiB write/verify runs
with distinct seeds, and reset recovery on the connected COM9 badge.
The hardware ID is `0d 5d 53`.

Native RP2350 PulseIn capture of GP12 measures the FPGA system clock divided
by 65536. Three samples were 51.4074, 51.4096 and 51.4131 MHz. Using the
median, both write and read throughput were **0.284031 MB/s** (decimal).
Each 64 KiB phase took **11,862,016 FPGA cycles**, or 181 cycles/byte.
The PSRAM SCK was approximately **12.85 MHz**.

These rates include FPGA transaction/controller overhead and read
verification, but exclude USB/CircuitPython command transport. Client
`read()` and `write()` still issue one command per byte.
See `validation/spi_throughput.log`.

## Quad hardware is not passing

The experimental controller sends SPI `35` to enter QPI and uses quad
`02` writes with configurable bursts. Several quad read variants were tested:

| Variant | Approximate SCK | Hardware result |
| --- | ---: | --- |
| EB, six dummy clocks, rising-edge capture | 12.85 MHz | Read alignment errors |
| EB, six dummy clocks, boundary/falling-edge capture | 12.85 MHz | Some values correct; other patterns corrupted |
| Same EB capture with a slower clock | 3.21 MHz | Corruption remains |
| 0B, four dummy clocks, rising-edge capture | 12.84 MHz | Readback fails |
| EB boundary/falling capture, faster system clock | 51.40 MHz | Readback fails |

The current source uses the datasheet-framed `0B`/four-dummy/rising-edge
implementation. QPI is disabled by default. The reported QPI flag indicates
the initialization sequence sent `35`; it is not independent proof of the
chip's operating mode.

A comparison test now prefills memory through SPI with the complement of
the quad write pattern, preventing retained data from masking failed writes.
Seven of eight quad-written bytes were then read correctly by SPI; the final
byte remained at its prefilled value. Earlier comparisons without distinct
prefill overestimated write correctness. See
`validation/qpi_cross_mode_prefill.log` and
`validation/qpi_read_failure.log`. Both read and write operation therefore
need further hardware debugging. **No verified quad throughput is available.**

FPGA trace capture (`TRACE=1`, opcode 9) is available for sampling analysis.
The 103.34 MHz-system-clock EB build passed final internal nextpnr timing
at 114.61 MHz maximum frequency; this does not validate external PSRAM I/O
timing or establish an electrical cause for the observed failures.

Strict lint and five SPI/QPI protocol/wiring simulations pass for the current
0B source, including 128-byte bursts at a 100 MHz simulation clock. The model
is a behavioral protocol model, not a vendor timing model. Simulation success
does not override the failing quad hardware tests. No complete 8 MiB quad
test has passed, and the faster variants are not recommended for use yet.

## Reproduce

From this directory in WSL/Linux:

```sh
make test lint
make all BUILD=build/spi_current QPI=0 SPI_BURST=0 OSC_DIV=6 HALF_PERIOD=2 BURST_BYTES=32
# Experimental only:
make all BUILD=build/qpi_0b_12mhz QPI=1 OSC_DIV=6 HALF_PERIOD=2 BURST_BYTES=16
```

Use a new build directory when changing parameters: parameter changes alone
do not invalidate existing Make targets. Copy the chosen bitstream and
`badge/psram.py` into `/apps/psram_j1/`, then execute
`scripts/device_benchmark.py` through `scripts/repl_run.py`.

The badge's root `code.py` is unchanged, SHA256
`50278b84a44c3f3d5f04d76bd0898d125c7ab836dc0bc524cae453584dd96165`.
Programming uses the volatile FPGA configuration path.

Before adding serial bursts, `build/spi_current/fpga_psram_j1.bit` was loaded
back onto the badge and passed the complete benchmark script. Median clock
was 51.4165 MHz and read/write rates were 0.284069 MB/s, with the same
11,862,016 cycles per 64 KiB phase. See
`validation/spi_current_throughput.log`. Its 126,688-byte bitstream SHA256 is
`0c843eab83fc1abf406253a2e32322b73477a5ce8967044fb5f1034a59c3197f`.
The badge was subsequently upgraded to the passing fast serial-burst
configuration described in `THROUGHPUT_REPORT.md`.
