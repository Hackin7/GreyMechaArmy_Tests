# Game Boy / Game Boy Color port implementation status

Date: 2026-07-19

## Implemented

- Pinned MiSTer Game Boy core import at commit
  `7a5ff50528cd9c1d13ffb675e7df8506bffaa078`.
- GHDL-to-Verilog conversion for the T80/GBse CPU and GBC audio core.
- Army top level using the external 16 MHz clock, 64 MHz panel domain, and
  timing-driven 16 MHz system domain.
- Exact 8.388608 MHz / 4.194304 MHz Game Boy enable generation.
- Host-loadable 32 KiB BRAM cartridge mode.
- 8 KiB, two-way, 256-byte-line ROM cache and emulation-clock stall handling.
- CRC-16 framed host protocol, cache-miss status response, and atomic packet
  commit.
- CircuitPython launcher using GP8-GP11 plus GP13 IRQ. Cache fills are read
  directly from the ROM file, so a 4 MiB cartridge is not copied into RP2350
  RAM.
- Native 160x144 RGB565 output centered on the 240x240 GC9A01 using two
  160-pixel line buffers rather than a frame buffer.
- Debounced controls, A+B Select chord, stereo-to-mono mix, and sigma-delta
  buzzer output.
- Board pin constraints and staged Makefile targets.

## Verification completed

- All eleven individual Blargg `cpu_instrs` ROMs pass in full-system Verilator
  simulation. The harness loads a 32 KiB cartridge, runs the real CGB boot ROM,
  captures writes to SB/SC, and requires each ROM's serial `Passed` signature.
- Restoring boot-ROM execution fixed the interrupt and control-flow tests that
  failed when the CPU was released at address zero without Game Boy register
  initialization. The two longest groups complete at about 128 million and
  158 million system clocks, so the suite gate uses a 200-million-clock limit.
- Six Python model/protocol tests pass: CRC reference vector, frame round trip,
  corrupted-frame rejection, cache-miss status, exact clock-enable counts, and
  two-way LRU behavior.
- The generated CGB boot ROM contains exactly 4096 bytes.
- Both upstream VHDL blocks convert successfully with GHDL synthesis.
- The 32 KiB BRAM build completed ECP5 synthesis with zero structural errors:
  12,195 LUT4 logic cells, 3,754 flip-flops, and 47/56 DP16KD blocks.
- Initial nextpnr placement and routing completed. The panel domain reached
  92.22 MHz. The initial 32 MHz system choice reached 25.58 MHz, which led to
  the current 16 MHz PLL retune and explicit derived-clock constraints.

## Open release gates

1. WSL Yosys/nextpnr/ecppack builds completed: both BRAM and cache-mode
   bitstreams meet the 16 MHz core and 64 MHz panel constraints.
2. Run a generated 32 KiB diagnostic ROM on the physical Army badge and verify
   pixels, buttons, audio, and reset/run sequencing.
3. Integrate save-cache fill/writeback with the host and pass power-cycle save
   persistence tests. The current save-cache RTL tracks dirty lines but is not
   connected to a persistence transport.
4. Run public/homebrew MBC1, MBC3, and MBC5 mapper fixtures in cache mode.
5. Measure cache-miss latency and execute the long-run soak tests in
   `docs/testplan.md`.

The final toolchain rerun could not be performed in this session because the
Docker FPGA images exhausted the host system volume. The temporary images and
large generated JSON were removed, and all source files were checked for
truncation; `rtl/top.v` was restored and the model suite was rerun afterward.

## Deliberately deferred features

- Save states/rewind, Game Genie, SGB, link cable, camera, infrared, and rumble.
- Rocket Games mapper header decoding; its unsupported SystemVerilog array
  initializer is disabled in the v1 open-source synthesis path.
