# GreyMecha/Army Game Boy and Game Boy Color

This subtree ports the portable MiSTer Game Boy core to the GreyMecha/Army
ECP5-25K badge. The guest CPU, PPU, APU, memories, and cartridge mapper execute
on the FPGA. The RP2350 configures the FPGA and provides ROM/save storage; it is
not the emulated CPU.

The implementation is staged:

1. `BRAM_ROM=1` provides a host-loadable 32 KiB cartridge for deterministic
   no-mapper bring-up.
2. `BRAM_ROM=0 FLASH_ROM=0` uses the FPGA cartridge cache serviced by CircuitPython.
3. `BRAM_ROM=0 FLASH_ROM=1` reads cartridges directly from ECP5 flash at
   `0x100000`, supporting one ROM up to 8 MiB. Build with `make bit-flash`.

See [badge deployment](badge/README.md) for the complete CircuitPython files,
including the supplied Python/PIO FPGA programmer. No custom native C module
is required. Run Defcon simulation with `make sim-flash-defcon
DEFCON_ROM=/path/to/defcon.gbc`; supply your own ROM.

The design uses the external 16 MHz oscillator, a 16 MHz system clock, a 64 MHz
panel clock, native 160x144 output centered on the 240x240 GC9A01, mono buzzer
audio, and the same board pinout as `arduboy_fx`.

Cached-ROM builds default to a 16 KiB ROM cache: 32 sets, two ways per set,
256-byte lines, and least-recently-used replacement. A miss stalls the core
until the complete line arrives; cartridge RAM remains separate. The flash
build uses 55 of the ECP5-25K's 56 BRAM blocks. For the previous
8 KiB geometry, use `make bit-flash CACHE_SET_BITS=4`; the default is 5.
`make sim-rom-cache` tests both sizes, including replacement, all sets,
line-end bytes, and reset invalidation. Rebuild when changing parameters;
ordinary `make bit` does not track parameter changes in existing outputs.

The native panel output defaults to `PANEL_SWAP_RB=1`, matching the working
Arduboy driver for the badge's BGR colour order. Core and line-buffer pixels
remain RGB565; red/blue are swapped only when serialized. Use
`make bit-flash PANEL_SWAP_RB=0` for a panel with RGB order instead.
`make sim-panel-colours` checks both modes, pure colours, asymmetric brown,
the initial white clear, and two complete scanlines. The Acid2 panel model
decodes the physical badge's BGR wire order before comparing RGB images.

## Build dependencies

- GHDL with synthesis support (generates the CPU and audio Verilog from VHDL)
- Yosys with ECP5 support
- nextpnr-ecp5
- Project Trellis `ecppack`
- Python 3

Build the deterministic first-stage bitstream with:

```bash
make BRAM_ROM=1 bit
```

Build the CircuitPython-serviced cache configuration with:

```bash
make BRAM_ROM=0 BUILD=build/cache GEN=build/generated GHDL_WORK=build/ghdl LOG=build/cache/log bit
```

Keep the two configurations in separate output directories. `BRAM_ROM` is a
build-time parameter, so using the same `build/` path can otherwise reuse a
bitstream from the other configuration.

Run deterministic host/model tests with:

```bash
make test
```

Build and run the full RTL against Blargg's eleven individual CPU instruction
ROMs with:

```bash
make sim-cpu-suite
```

The testbench boots the real CGB boot ROM, observes the cartridge's writes to
the Game Boy serial registers, and accepts only the ROM's own `Passed` result.
Use `make sim-cpu` for the shorter `01-special.gb` single-ROM gate.

Generated HDL, logs, reports, and bitstreams live under `build/` and are not
source artifacts.

## Current bring-up order

1. Run `make test`.
2. Run `make BRAM_ROM=1 bit` and inspect utilization/timing.
3. Install `badge/main.py` and the bitstream under `/apps/gameboy_gbc/`.
4. Load a generated 32 KiB smoke ROM while the guest remains in reset.
5. Verify native panel output, controls, and audio.
6. Switch to `BRAM_ROM=0` only after the cache/SPI stress tests pass.

See the [implementation plan](docs/plan.md) and
[test plan](docs/testplan.md) for scope and release gates. Current measured
results and remaining hardware gates are in
[implementation status](docs/implementation-status.md).
