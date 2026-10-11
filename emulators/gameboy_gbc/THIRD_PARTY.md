# Third-party source manifest

## MiSTer Game Boy core

- Repository: <https://github.com/MiSTer-devel/Gameboy_MiSTer>
- Pinned commit: `7a5ff50528cd9c1d13ffb675e7df8506bffaa078`
- Imported paths: `rtl/`, `BootROMs/`, `Gameboy.sv`, and upstream README
- Local path: `vendor/Gameboy_MiSTer/`
- License: per-file licenses. The main Game Boy RTL is GPL-3.0-or-later. The
  T80 CPU files retain their upstream notices. Boot ROM sources are derived
  from SameBoy and carry MIT notices in the source files.

The import is pinned, with two documented synthesis portability edits:

- `rtl/gbc_snd.vhd` replaces a scalar `'high` reference with its equivalent
  literal `100` for GHDL synthesis.
- `rtl/mappers/mappers.v` uses plain internal wires because the open-source
  Yosys frontend does not parse the upstream `tri0`/`tri1` vector declarations.

The Rocket mapper's unsupported unpacked-array initializer is disabled for the
v1 MBC1/MBC3/MBC5 gate. GreyMecha wrappers and feature stubs otherwise live
outside the vendor directory.

## GreyMecha GC9A01 modules

The files under `rtl/panel_common/` were copied from the repository's existing
`arduboy_fx/rtl/fast_oled/` implementation. They remain part of this repository
and provide the board-proven panel reset and initialization sequence.

## CircuitPython FPGA programmer

`badge/hardware/fpga/` contains the compatible GreyMecha Python/PIO loader
and flash programmer migrated from `pio_flash_speedup/filesystem/hardware/fpga/`.
Original per-file notices are retained. The JTAG PIO transport documents
adaptation from MIT-licensed pico-dirtyJtag; `flash_pio.py` carries a BSD notice.
CircuitPython and `adafruit_pioasm` are runtime dependencies, not vendored here.
