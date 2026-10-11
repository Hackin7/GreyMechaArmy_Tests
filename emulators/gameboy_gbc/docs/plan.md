# GreyMecha/Army Game Boy and Game Boy Color Port

## Goal

Build one ECP5 bitstream that runs the complete Game Boy/Game Boy Color system on
the GreyMecha/Army FPGA. The RP2350 is a loader and storage service only: it must
not execute the emulated CPU.

The first release must boot DMG and CGB software, display native 160x144 video,
produce game audio, accept all eight Game Boy controls, load ROMs from the
RP2350 flash, and persist cartridge save RAM.

## Source and licensing

- Use a pinned revision of the
  [MiSTer Game Boy core](https://github.com/MiSTer-devel/Gameboy_MiSTer) as the
  portable core source.
- Consult the
  [budude2 Analogue Pocket port](https://github.com/budude2/openfpga-GBC) for
  integration fixes, but do not import its APF, Quartus, or Cyclone V wrapper.
- Preserve every upstream license header and add a third-party source manifest
  recording repository URL, commit, files imported, and license.
- Do not commit Nintendo boot ROMs or commercial cartridge images.
- Include the open MiSTer/SameBoy-derived boot ROMs by default and allow local,
  uncommitted 256-byte DMG and 2304-byte CGB BIOS overrides.

## Repository layout

Create an isolated `gameboy_gbc/` subtree alongside `arduboy_fx`:

- `vendor/`: pinned portable core and license notices.
- `rtl/`: GreyMecha top level, clocks, memory wrappers, cartridge cache, host
  bridge, display, controls, and audio.
- `badge/`: launcher plus the native CircuitPython flash/SPI service.
- `sim/`: RTL testbenches, models, and permissively licensed or generated ROM
  fixtures.
- `docs/`: protocol and bring-up notes specific to this port.

The new port must not depend on generated files inside `arduboy_fx`; reusable
RTL should be copied with attribution or promoted to a deliberately shared
module.

## FPGA architecture

The ECP5 contains and clocks the Game Boy CPU, PPU, APU, mapper, system RAM,
boot ROM, cartridge caches, video line buffers, and audio output.

Use the external 16 MHz board oscillator and an ECP5 PLL to generate:

- 16 MHz system and host-bridge domain (retuned after ECP5 timing analysis).
- 64 MHz GC9A01 panel domain.
- Exact long-term 4.194304 MHz and 8.388608 MHz Game Boy clock-enable pulses
  from a phase accumulator in the 16 MHz domain.

Do not gate a physical clock in fabric. DMG/CGB normal and double-speed behavior
must use clock enables already expected by the portable core.

Replace Altera-specific PLL, RAM, and FIFO modules with inferred or ECP5-native
implementations. Convert required VHDL modules to build-only Verilog with
`ghdl-llvm --synth --out=verilog`, then synthesize with Yosys, place and route
with nextpnr-ecp5, and package with ecppack.

## FPGA memory allocation

Keep the following inside ECP5 block RAM:

- 32 KiB GBC WRAM.
- 16 KiB GBC VRAM.
- HRAM, OAM, palette RAM, and boot ROM.
- 8 KiB two-way cartridge ROM cache using 256-byte lines.
- 2 KiB two-way save cache using 64-byte lines.
- Two 160-pixel RGB565 display line buffers.

No 240x240 framebuffer is allowed. The completed design must use no more than
the device's 56 DP16KD blocks.

## ROM storage without RP2350 PSRAM

ROM files reside in the RP2350's W25Q128 16 MiB flash filesystem. V1 accepts
uncompressed `.gb` and `.gbc` files up to 4 MiB.

The FPGA cartridge cache is blocking and permits one outstanding miss. A miss
stalls guest CPU cartridge access while the display engine, audio buffering,
and host transport continue. Sequential-line prefetch should request the next
256-byte line when the current line is filled.

A native CircuitPython module must:

- Keep the selected ROM file open and validate its size and cartridge header.
- Seek and read cache lines without Python-level byte copying.
- Use fixed internal-SRAM bounce buffers for SPI transfers.
- Measure cache-fill latency and expose counters for hits, misses, prefetch
  hits, CRC failures, and service latency.

If filesystem-backed reads cannot sustain at least 1.5 MiB/s or have cache-fill
99th-percentile latency above 400 microseconds, reserve a contiguous 4 MiB raw
flash slot in the custom CircuitPython flash layout and stage the active ROM
there before releasing FPGA reset.

## RP2350-to-FPGA interface

Use the established interconnect:

- Interconnect 0: SPI clock.
- Interconnect 1: RP2350 to FPGA data.
- Interconnect 2: FPGA to RP2350 data.
- Interconnect 3: active-low chip select.
- Interconnect 5: active-high FPGA request-pending interrupt.

The RP2350 is SPI master. Target a 20 MHz hardware SPI clock. The FPGA must use
an SPI-clock-domain shift engine and a dual-clock FIFO or equivalent verified
handshake into the 16 MHz domain.

Frames contain a protocol version, opcode, sequence number, 32-bit little-endian
address, 16-bit little-endian length, optional payload, and CRC16-CCITT. The
protocol supports reset, configuration, status, request retrieval, ROM fill,
save fill, save writeback, and fault acknowledgement. Invalid lengths, CRC
failures, sequence mismatches, or unsupported opcodes set a sticky protocol
fault visible to the launcher.

## Cartridge behavior

V1 supports:

- ROM-only cartridges.
- MBC1.
- MBC2, including its internal 4-bit RAM behavior.
- MBC3 ROM/RAM banking.
- MBC5, including the ninth ROM-bank bit.
- Battery-backed cartridge RAM up to 128 KiB.

The launcher selects DMG or CGB mode from the CGB header byte, with an explicit
`auto`, `dmg`, or `cgb` override. Header checksum failures generate a warning;
invalid or unsupported size/mapper fields prevent launch.

MBC3 RTC games may boot in V1, but the RTC remains static. Host-backed RTC,
rumble, camera, infrared, link cable, SGB, save states, and fast-forward are
post-V1 features.

## Save persistence

The FPGA save cache is write-back. Dirty evictions are transferred to a native
RP2350 internal-SRAM save buffer; individual guest writes must never trigger a
flash erase or program operation.

Save files use `/apps/gameboy_gbc/saves/<rom-stem>.sav` and the cartridge
header's declared RAM size. The launcher checkpoints every two minutes while
the guest is paused and flushes on clean exit. Writes use a temporary file,
sync, and rename so an interrupted checkpoint retains either the previous or
new complete save.

## Video

Reuse the proven GC9A01 initialization sequence, then clear the 240x240 panel
once and program a 160x144 address window at `(40, 48)`.

Convert the core's RGB555 pixels to RGB565 and capture them into ping-pong
160-pixel line buffers. Stream completed lines over the 64 MHz panel interface.
The border remains black. The design must not scale or interpolate pixels in
V1.

## Controls and audio

Control mapping:

| Game Boy control | GreyMecha input |
| --- | --- |
| Left | `btn[0]` |
| Up | `btn[1]` |
| Start | `btn[2]` |
| Down | `btn[3]` |
| Right | `btn[4]` |
| A | Grey button |
| B | Secondary button |
| Select | A+B chord |

An active Select chord suppresses A and B, so an independent A+B combination
is not available in V1. Reset and exit are launcher-controlled.

Mix the portable core's stereo samples to mono with saturation and drive the
board buzzer through first-order sigma-delta output. Preserve channel activity
and underrun counters for debugging.

## Implementation milestones

1. **Core feasibility:** vendor and license the portable core, replace vendor
   primitives, synthesize an empty-cartridge build, and record LUT, register,
   DSP, EBR, and timing results.
2. **Board plumbing:** verify the 16 MHz input, PLL lock, panel test pattern,
   controls, buzzer, SPI loopback, and request interrupt.
3. **Block-RAM cartridge:** load and boot one generated 32 KiB DMG ROM and one
   generated 32 KiB CGB ROM entirely from FPGA RAM.
4. **Flash-backed cartridge:** implement the cache and native RP2350 service,
   then pass sequential, randomized, retry, and fault-injection tests.
5. **Mappers and saves:** enable ROM-only, MBC1, MBC2, MBC3, and MBC5 fixtures;
   verify dirty eviction, checkpoint, and reload.
6. **Launcher and packaging:** add ROM selection, validation, mode override,
   counters, fault reporting, and installable bitstream/application packaging.

## Completion criteria

The port is complete when it:

- Fits the ECP5-25K within 56 DP16KD blocks and closes timing in all declared
  clock domains.
- Boots both DMG and CGB generated diagnostic ROMs.
- Loads ROMs up to 4 MiB from RP2350 flash at full emulated speed.
- Passes the supported mapper and save-persistence matrix.
- Produces stable centered 160x144 video at the native Game Boy refresh rate.
- Produces recognizable audio without persistent underruns.
- Implements every direct control, Select chord, launcher reset, and exit.
- Completes a 30-minute hardware soak without cache deadlock, protocol fault,
  corrupted video, or save corruption.
