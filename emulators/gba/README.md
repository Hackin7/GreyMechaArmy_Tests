# GreyMecha/Army v2 GBA (simulation-first)

This removes the Analogue Pocket shell from `mincer-ray/openfpga-GBA` and
wraps its `gba_top` behind platform-neutral memory, input, pixel, and audio
interfaces. The large memories are simulation models, not an ECP5 mapping.

Run in WSL:

```bash
cd "/mnt/c/Users/zunmun/Documents/Stuff/Github/PERSONAL PROJECTS/GreyMechaArmy_Tests/emulators/gba"
make sim
```

The default test needs GHDL. It runs the original mostly-VHDL core directly,
using a tiny original ARM program in place of the Nintendo BIOS. The smoke test
checks that the ARM core executes into its terminal loop, the mode-3 display
control and framebuffer stores read back exactly, and the PPU advances through
active scan. No Nintendo BIOS or commercial ROM is included.

The simulation deliberately uses large behavioral memories; fitting them into
the Army v2 RAM budget is a later hardware-integration step. The platform-neutral
SystemVerilog wrapper and memory model are retained for that work.

`make verilog` is experimental. GHDL 6 can synthesize the complete core, but its
Verilog backend currently lowers resolved VHDL record inouts as an undeclared
identifier, so Icarus cannot elaborate the generated netlist. A strict colored
mode-3 output-pixel assertion is also still open in the vendor-neutral dual-port
VRAM shim; the default smoke test verifies the CPU writes and PPU scan instead.

Upstream: https://github.com/mincer-ray/openfpga-GBA at
`b08568fa60ff6f5f918cca5763f5b1923ed2d3db`, GPL-2.0.
