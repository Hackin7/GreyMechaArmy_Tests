# GBA flash quad-read experiment

The GBA cartridge reader now has an opt-in W25Q128JV quad-output path. The fastest **hardware-passing candidate tested on COM9 on 2026-10-13** has approximately **79.7 MHz SCK**, derived from the FPGA's internal oscillator. It achieved **11.56 MB/s** in the same sample workload as the **1.27 MB/s** SPI baseline (about **9.1x**).

This result validates the actual GBA flash cache in a small, read-only FPGA test image. Full-emulator hierarchy elaboration passes, but complete-emulator routing and game acceptance at this clock remain pending. The normal build retains SPI by default. The original badge GBA image was restored after testing.

## Hardware results

| Candidate | Derived SCK | Result | Cache-service MB/s |
| --- | ---: | --- | ---: |
| Existing single SPI, 0Bh | 12.86 MHz | Pass | 1.27 |
| Quad output, four controller cycles/SCK | 12.86 MHz | Pass | 4.40 |
| Quad output, two cycles/SCK, corrected FIFO handoff | 71.95 MHz | Pass | 11.52 |
| Final source, PLL core divider 30 / flash divider 4 | 77.13 MHz | Pass | 11.56 |
| Final source, PLL core divider 31 / flash divider 4 | 79.70 MHz | Pass | 11.56 |
| Earlier ~83 MHz candidates, direct and registered inputs | ~82 MHz | Readback mismatches despite passing internal timing | — |
| ~93 MHz candidate | — | Fails internal timing; not loaded | — |

An intermediate ~74 MHz image produced no valid host response and was not accepted. Earlier fast experiments also exposed a pending-write/full-flag race in the FIFO handoff; the final reader includes a byte-boundary settling state. Failed versions are not recommended.

Each comparison reads five regions three times (11,520 bytes per mode), with independent JTAG reads as the reference. Regions cover nonblank ROM/header data, unaligned cache/page/64 KiB boundaries, and the highest supported cartridge address. The final stress run adds eight distributed 256-byte regions and repeats all thirteen regions five times: **29,440 verified bytes, 130 cache misses, zero mismatches**, approximately 79.67 MHz SCK. Its different address mix measures **12.06 MB/s**; use the identical-workload 11.56/1.27 figures for the speedup comparison.

These are sampled read tests, not a complete 8 MiB verification or a temperature/voltage qualification. Rates use FPGA core-cycle counters while the cache services requests and exclude USB/REPL transport. They include cache fills and subsequent word/pair hits. Clock frequency is calibrated with RP2350 PulseIn on GP12, reading the FPGA core-clock/65536 reference; SCK is derived from the PLL ratio and controller divider. Byte-boundary/FIFO stalls stretch SCK's low intervals. These numbers do not measure game FPS.

Evidence is retained in `../validation/flash-qspi-*.json`; generated build/timing logs remain under `../build/flash-benchmark/`.

## Protocol and wiring

The reader sends **6Bh + a 24-bit address on IO0 + eight dummy clocks**, then receives high/low nibbles on IO[3:0]. A 256-byte line uses **552 SCK edges**, compared with 2,088 for the existing 0Bh reader. Physical address remains `0x100000 + cartridge byte address`; the first MiB of configuration flash is never written by the test.

| Flash signal | FPGA package pin |
| --- | --- |
| CS# | N8 |
| IO0 / MOSI, bidirectional during reads | T8 |
| IO1 / MISO | T7 |
| IO2 / WP# | M7 |
| IO3 / HOLD# | N7 |
| SCK | ECP5 USRMCLK |

IO2/IO3 mapping was checked against the cached published GreyMecha PCB (`sd_io2`/`sd_io3`). This is the onboard FPGA configuration/cartridge flash, separate from the RP2350 flash and external J1 PSRAM. [Board source](https://github.com/NUSGreyhats/greybadge25/blob/main/hardware/greybadge_pcb/greybadge_pcb.kicad_pcb).

Initialization reads SR2 (35h). If QE is clear, it preserves the other bits and uses **50h followed by 31h** to set QE in the **volatile** status register, then checks QE. A failed QE check reports a fault and stops reads. IO0 releases during dummy clocks and remains an input until CS# releases. The protocol does not enter QPI or continuous-read mode, erase sectors, or program cartridge bytes. [Winbond W25Q128JV datasheet, sections 8.2.5 and 8.2.9](https://www.winbond.com/resource-files/w25q128jv%20revg%2004082019%20plus.pdf).

The original 256-byte GBA cache, little-endian word pairs, FIFO and synchronized request handoff are retained. The full emulator uses a second PLL for faster cartridge reads, keeping its existing core, panel and PSRAM clocks. Flash readiness/fault crosses two synchronizer stages into the host status logic. Flash initialization runs while the guest CPU is stopped, avoiding a startup dependency on the host's run command.

## Reproduce the accepted reader image

From `emulators/gba` in WSL:

```sh
make test-flash test-qspi test-qspi-fast
make flash-benchmark-bit FLASH_QSPI=0 FLASH_TAG=0
make flash-qspi-bit
```

`flash-qspi-bit` selects `FLASH_QSPI=1 FLASH_CYCLES=2 FLASH_RX_REGISTER=0 PLL_CORE_DIV=31 PLL_FLASH_DIV=4 FLASH_MHZ=164 FLASH_TAG=final80`. The internal OSCG uses DIV=6. The PLL feedback core output is about 20.57 MHz on this badge; flash controller/core is 31/4, and SCK is half the controller clock. The 164 MHz constraint exceeds the existing 21 MHz core bound multiplied by 31/4 (162.75 MHz).

The routed reader image uses 1,961/24,288 logic cells, 816 flip-flops, one block RAM, zero multipliers and one PLL. Final achieved/required frequencies are **167.90/164.02 MHz** for the flash controller and **100.17/21.00 MHz** for the core. Internal timing does not establish the external flash timing margin.

Accepted artifact: `build/flash-benchmark/gba-flash-final80.bit`, 129,069 bytes, SHA256:

```text
27b08a3adeff634b961cb112cc06e6e0a61b5f8d2720dacd6ad183a49a673ff1
```

Run the hardware comparison from the repository root in Windows:

```powershell
python emulators/gba/tools/flash_qspi_test.py --port COM9 --drive E:/ --quad-bit emulators/gba/build/flash-benchmark/gba-flash-final80.bit --flash-ratio 7.75 --quad-cycles 2 --log-name flash-qspi-final80
```

For the longer check, add `--extra-regions 8 --repeats 5 --skip-spi --log-name flash-qspi-final80-stress`. The script flushes and reuses one temporary image file because badge storage is limited. It reads the golden bytes through JTAG, temporarily loads each test image through the existing deferred loader, then restores the original volatile SR2 value and `/apps/gba/gba.bit`. It verifies that the normal bitstream and root `code.py` hashes are unchanged, and removes/restores its temporary file. The restored emulator is paused; start the normal application to run a game.

For a complete-emulator candidate, after generating the GBA core:

```sh
make check-qspi-top
make bit FLASH_QSPI=1 FLASH_CYCLES=2 FLASH_RX_REGISTER=0 PLL_CORE_DIV=31 PLL_FLASH_DIV=4 FLASH_MHZ=164 BOARD_WORK=/tmp/greymecha_gba_qspi_board BOARD_LOG_TAG=qspi-board BOARD_BIT=build/gba-qspi.bit
```

Do not substitute the reader-test bitstream for the game image. Complete-emulator resource/timing closure and game validation are separate checks; the reader-test timing numbers above do not apply to that larger design. `bit-existing-core` can reuse `build/generated/gba_top_board.v` only when it matches the intended core sources and generation options.
