# Faster single-bit PSRAM reads

The GBA PSRAM arbiter/PHY passed a full **8 MiB write/read verification on COM9 at approximately 51.4 MHz read SCK**, with writes and initialization still around 25.7 MHz. Read throughput increased from **1.14 to 1.91 MB/s**, approximately **67%**. This is the GBA four-byte word-transfer workload, not the standalone demo's longer bursts or a game-FPS measurement.

## Recorded hardware results, 2026-10-13

| Configuration | Read SCK | Write SCK | Read MB/s | Write MB/s | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| Original asynchronous PHY | 25.72 MHz | 25.72 MHz | 1.143 | 1.247 | Full 8 MiB pass |
| Faster reads, final artifact | 51.41 MHz | 25.70 MHz | 1.913 | 1.265 | Full 8 MiB pass |
| Next ~62 MHz read candidate | — | — | — | — | Routed timing failed; not loaded |

The faster reader passed three full-memory runs, including the final rebuilt artifact. Boundary preflight also passed. The final run uses 136,314,880 write cycles and 90,177,536 read/verify cycles at a calibrated 20.5627 MHz core clock. An 8 MiB read/verify phase takes approximately **4.39 seconds**, versus **7.34 seconds** at the baseline speed.

Rates are decimal MB/s, measured by FPGA cycle counters. They include the arbiter, request/acknowledgement crossings, command/address/dummy clocks, four-byte transfers and comparison work; USB transport is excluded. GP12 provides core-clock/65536 for RP2350 PulseIn calibration. Read SCK is core frequency times 2.5; write SCK is core frequency times 1.25. This is a complete address-space pattern check, not exhaustive values or temperature/voltage qualification.

Evidence: `../validation/psram-speed-*-2026-10-13.json`. The benchmark overwrites volatile PSRAM, never cartridge flash. It restores the normal FPGA image afterward; launch the normal application to initialize game RAM again.

## Implementation

`spi_burst.v` now accepts `READ_HALF_PERIOD` independently of its existing write divider. Optional `READ_FALLING=1` captures MISO immediately before generating the falling SCK edge, allowing a full SCK period after the preceding falling edge for the chip output to settle. Defaults preserve the existing SPI demos' behavior.

For the accepted profile, the primary PLL's RAM output doubles from nominal 50 to 100 MHz. Writes and initialization use divider two, reads use divider one. The GBA core and panel PLL outputs retain their original frequencies. The 0Bh fast-read command and eight dummy clocks are unchanged. Chip-select spacing doubles to eight PHY cycles and startup delay doubles to 40,000 PHY cycles, preserving their absolute durations.

The chip is the external APS6404L on J1. The manufacturer specifies up to 84 MHz for linear fast-read bursts, with chip-select duration and spacing requirements; this test uses the existing single-bit protocol. [AP Memory datasheet](https://www.apmemory.com/en/downloadFiles/032411212009597427).

## Build and repeat

From `emulators/gba` in WSL:

```sh
make test-psram test-psram-fast
make psram-benchmark-bit PSRAM_BENCH_TAG=baseline
make psram-fast-read-bit
```

The fast target selects RAM PLL dividers 20/4, write/init half-period 2, read half-period 1, falling-edge capture, eight-cycle spacing and 40,000-cycle startup. The benchmark constraints use 24 MHz core and 120 MHz PHY, covering nominal OSCG frequency plus the stated 15% upper variation. [Lattice oscillator reference](https://www.latticesemi.com/view_document?document_id=32323). Final routed achieved/required values are **125.93/120.00 MHz** for the PHY and **93.70/24.00 MHz** for the core. The test image uses 2,431 logic cells, 1,269 flip-flops, five block RAMs and one PLL on the ECP5-25K.

Accepted image: `build/psram-benchmark/gba-psram-read51.bit`, 149,007 bytes, SHA256:

```text
09d3c6c7cef64c0bf7cfc7a515ffc9d7a197feb5211654a6adf84749dc4b0227
```

From the repository root in Windows:

```powershell
python emulators/gba/tools/psram_benchmark.py --port COM9 --drive E:/ --bit emulators/gba/build/psram-benchmark/gba-psram-read51.bit --spi-core-ratio 2.5 --write-core-ratio 1.25 --log-name psram-speed-read51-final
```

The runner flushes the staged file, calibrates the core clock, performs boundary checks and the autonomous full-memory comparison, then restores `/apps/gba/gba.bit` and the previous temporary-file contents. Normal FPGA-image hashes are checked during restoration.

The complete emulator has an opt-in `PSRAM_FAST_READ=1` parameter. Full hierarchy elaboration with this option passes. To build a separate game-image candidate:

```sh
make bit PSRAM_FAST_READ=1 BOARD_WORK=/tmp/greymecha_gba_psram_fast BOARD_LOG_TAG=psram-fast BOARD_BIT=build/gba-psram-fast.bit
```

That option also selects conservative 24/97/120 MHz core/panel/RAM constraints. The complete emulator must pass its own resource/timing closure and game tests; the small benchmark's timing results do not establish those. The default remains `PSRAM_FAST_READ=0`, and the normal badge image was restored after these experiments.
