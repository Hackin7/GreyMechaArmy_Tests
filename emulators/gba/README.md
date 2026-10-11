# GBA on GreyMechaArmy

The core is `mincer-ray/openfpga-GBA` at
`b08568fa60ff6f5f918cca5763f5b1923ed2d3db`, GPL-2.0. The board target is
**LFE5U-25F/CABGA256: 24,288 LUTs, 56 block RAMs, 28 DSPs**.
Hardware acceptance is pending; simulation passes alone do not establish a
working hardware emulator. The first acceptance ROM is the local diagnostic,
followed by the mGBA autorun suite and physical screen/button checks.

The latest mapped build on 2026-10-12 uses 43/56 block RAMs, 27/28 DSPs
and 24,107/24,288 logic sites, down from the initial 40,436 sites. It is
within the resource budget; final routing and timing are pending.
The board shares DMA address adders and the CPU's
ADD/ADC/SUB/SBC datapath and ARM barrel shifter. Their arithmetic behavior
is exhaustively proved with Yosys SAT; the diagnostic also checks carry, borrow and
overflow flags after booting the open BIOS. Sprite priority/coverage
metadata now uses two block RAMs. The ARM general registers use distributed
RAM with native bank selection instead of copying banks through flip-flops.
Mutually exclusive instruction types share destination/block and
accumulator/Thumb-BL read ports without adding read latency.
The area mapping uses ABC's area objective without carry cells or wide LUTs.
This includes the object-window RAM and block-RAM panel command ROM.
Host transfer counters and bounds arithmetic now use the validated 8 MiB
range; exhaustive SAT checks preserve the original packet validation and
legal counter updates. Sprite line settings also use block RAM, retaining
their original registered read latency.
The 100 MHz core target placed but its estimated maximum was about 32 MHz.
The board now targets a nominal 20 MHz core with unchanged 80 MHz panel
and 50 MHz flash clocks. The internal oscillator makes these approximately
20.67/82.67/51.67 MHz; the LPF constrains them to 21/85/53 MHz.
Button counters use the core frequency bound. Flash and complete LCD-stream
simulations pass at these core/panel/flash clock ratios.
No GBA bitstream has been programmed on the board.

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
OR trees. It retains ARM instruction execution, DMA, timers, interrupt logic, audio
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
The cartridge cache is 64 entries; cache, OAM, palettes and sprite
priority/coverage metadata use block RAM. Sprite metadata clears one entry
per clock between scanlines; the next line waits for the clear to finish.
The object-window buffer also clears sequentially between lines and retains
its original registered read latency.
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
The diagnostic reports its checks and KEYINPUT values through SRAM.
Its eleven check flags must total `0x7ff`: EWRAM, IWRAM, their mirrors, SRAM,
lower VRAM, upper VRAM, ignored byte stores into sprite VRAM and ARM
arithmetic flags, ARM shifts and register banking. VRAM checks include duplicated byte stores, halfword
writes and mirrored reads. Fourteen boundary cases exercise ADDS, ADCS,
SUBS and SBCS with NZCV readback. The word at report offset 36 identifies
the first failed arithmetic case, or is zero when all cases pass. Another
66 fixed vectors check LSL, LSR, ASR, ROR and RRX, including zero and amounts
at and above 32 with both carry inputs. Offset 40 identifies their first
failed case, or is zero when all pass.
Offset 44 identifies the first failed banking case. The diagnostic executes
mode changes through all six physical ARM banks, checks each saved status
register, and exercises user-bank STM/LDM transfers while in FIQ mode.
It also checks MLA, UMLAL with carry and Thumb BL to verify that shared
ports retain the normal multiply operands and banked link register.
The current generated board core passes the open BIOS and this complete
diagnostic in Verilator, including pause, KEYINPUT and frame output. This
checks guest behavior with a variable-latency PSRAM model; physical SPI
memory, LCD and button paths have separate passing simulations.
The board CPU also fixes the upstream register-ROR carry result for nonzero
multiples of 32: the value stays unchanged and C receives bit 31, as required
by the [ARM7TDMI-S instruction set, section 4.5.2](https://iitd-plos.github.io/col718/ref/arm-instructionset.pdf#page=14).

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
