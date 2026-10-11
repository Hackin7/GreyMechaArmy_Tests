# Migration into GreyMechaArmy_Tests

The Game Boy project lives at `emulators/gameboy_gbc` as ordinary files in
the parent repository. It has no embedded Git repository and does not depend
on the original development workspace or the neighbouring Arduboy project.

The panel modules used by the working build are included in
`rtl/panel_common`. Compatible FPGA upload and flash-programming Python/PIO
modules are included in `badge/hardware/fpga`; see `badge/README.md` for deployment.

The current Game Boy menu entry programs/verifies the retained cartridge ROM
before launching. This migration preserves that current behavior. The callable
`main.app(hw_state)` remains available for a menu integration that only loads
the bitstream, and `main.program_rom_app(hw_state)` performs programming.

Generated build files, personal ROMs and installed-ROM metadata are excluded
from Git. `games/game.gb` is the existing smoke cartridge; simulation test
ROMs retain their source manifest. Supply Defcon separately with
`make sim-flash-defcon DEFCON_ROM=/path/to/defcon.gbc`.

The original development copy is retained as a recovery/reference copy.
Use this repository for subsequent development and commits.

## Validation on 2026-10-11

- All 14 model and flash-programmer tests passed (`make test`).
- SPI fast-read, dummy byte, 256-byte fill and cache-hit RTL simulation passed
  (`make sim-flash`).
- All 19 Python deployment/tool files passed syntax parsing.
- ECP5-25K synthesis and routing passed core timing at 16 MHz and panel timing
  at 64 MHz; 51 of 56 block RAMs are used.

The migration removes the unused `USRMCLKO` connection for compatibility with
the installed Yosys primitive definition. GHDL writes temporary generated HDL
to its Linux work directory before copying it to the Windows checkout, avoiding
slow per-line writes on the WSL-mounted filesystem.

No new hardware upload or Defcon gameplay test was performed during migration.
