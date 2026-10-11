# GBA on GreyMechaArmy

The core is `mincer-ray/openfpga-GBA` at
`b08568fa60ff6f5f918cca5763f5b1923ed2d3db`, GPL-2.0. The board target is
**LFE5U-25F/CABGA256: 24,288 LUTs, 56 block RAMs, 28 DSPs**.
Hardware acceptance is pending; simulation passes alone do not establish a
working hardware emulator. The first acceptance ROM is the local diagnostic,
followed by the mGBA autorun suite and physical screen/button checks.

The external-low-VRAM build on 2026-10-12 uses 38/56 block RAMs and
33,125/24,288 logic sites, down from 55 RAMs and 40,436 sites. It therefore
**does not fit yet**. A further build shares the DMA address adders; their
equivalence to the upstream updates is exhaustively proved with Yosys SAT,
including all addresses, transfer widths, address modes and cartridge
overrides. Its area is being measured. No GBA bitstream has been programmed
on the board.

Run the build commands in WSL from this directory. Required tools are GHDL,
Yosys, nextpnr-ecp5, ecppack, Icarus Verilog, Verilator, and arm-none-eabi-gcc.
The mGBA suite additionally needs devkitPro with devkitARM/libgba/libtonc.

```bash
make sim                 # Original VHDL core and tiny ARM smoke program
make test-board          # SPI/CRC/PSRAM host, buttons, complete LCD stream
make diagnostic bios suite
make board-core          # Generate portable board netlist
make test-renderer       # Compare shared engines with original renderer
make test-board-core     # Open BIOS, diagnostic RAM/save checks, pause, keys
make bit                 # Synthesis and place/route for the actual 25K FPGA
```

`make verilog` retains the original experimental resolved-record conversion.
The hardware path uses `tools/prepare_rtl.py` to lower those buses into explicit
OR trees. It keeps the original CPU, DMA, timers, interrupt logic, audio
registers, all rendering modes, sprites, windows and compositor. The board
serializes the four text-background engines and two affine-background engines,
waiting at HBlank for rendering to finish. The wrapper disables savestates;
the board source explicitly retains only that engine's reachable reset path.
Battery SRAM/flash/EEPROM are separate and remain supported.

BIOS and IWRAM join EWRAM, saves and the lower 64 KiB of VRAM in J1 PSRAM
through the repository's single-bit SPI controller. The upper 32 KiB of VRAM
and rendering line buffers remain on-chip. Four word caches preserve the
background fetchers' synchronous read interface and suppress valid tokens on
cache misses; CPU writes invalidate matching cached words. The core, host and
video clients share PSRAM with round-robin arbitration.
The cartridge cache is 64 entries; cache, OAM and palettes use block RAM.
The renderer matches the original for 17,280 pixels with both on-chip and
variable-latency external low VRAM, covering all six modes, layers, sprites,
transforms, windows, mosaic and blending.
The build permits undefined simultaneous read/write collisions for block RAM;
CPU write-cycle read outputs are unused. Generated netlists and memory files
live on the Linux filesystem under `BOARD_WORK`, normally
`/tmp/greymecha_gba_board`, to keep expensive synthesis passes off NTFS.

PSRAM byte map:

| Region | Base | Size / representation |
| --- | --- | --- |
| EWRAM | `0x00000` | 256 KiB |
| IWRAM | `0x40000` | 32 KiB |
| BIOS | `0x48000` | 16 KiB |
| EEPROM | `0x60000` | One logical byte per 32-bit word |
| SRAM/flash | `0x80000` | 128 KiB logical bytes, stride four |
| Lower VRAM | `0x100000` | 64 KiB; original byte enables and mirrors |

The cartridge occupies FPGA flash starting at `0x100000`, up to 8 MiB. BIOS
source pins, license and binary hash accompany the generated open BIOS.
The default build omits its splash animation while retaining initialization
and SWI implementations; `tools/build_bios.py --boot-logo` restores the splash.
The diagnostic reports its memory checks and KEYINPUT values through SRAM.
Its eight check flags must total `0xff`: EWRAM, IWRAM, their mirrors, SRAM,
lower VRAM, upper VRAM and ignored byte stores into sprite VRAM. VRAM checks
include duplicated byte stores, halfword writes and mirrored reads.

The LCD path reuses the proven Arduboy GC9A01 commands and SPI engine. It
streams black borders around a fitted 192?128 image, or a native 240?160 image.
Center+Up changes the viewport at a frame boundary. Grey is A, red is B,
center release taps Start, center+Down is Select, center+grey is L and
center+red is R. Host key injection can exercise all ten GBA buttons.

Run physical tests from Windows with Python and pyserial:

```powershell
python tools/hardware_test.py --port COM9 --drive E:/ diagnostic
python tools/hardware_test.py --port COM9 --drive E:/ suite --minutes 60
```

The runner stages `/apps/gba`, uses the existing NVM loader and a full MCU
reset, programs and verifies the selected cartridge, checks PSRAM boundaries,
boots the BIOS and checks the ROM's SRAM report. It preserves root `code.py`.
The diagnostic additionally checks injected buttons; the suite exports its
CRC-checked result report. Logs and reports go under `build/hardware/`.
The GBA menu entry is added after actual hardware acceptance.
