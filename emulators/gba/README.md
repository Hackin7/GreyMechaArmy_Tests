# GBA on GreyMechaArmy

The core is `mincer-ray/openfpga-GBA` at
`b08568fa60ff6f5f918cca5763f5b1923ed2d3db`, GPL-2.0. The board target is
**LFE5U-25F/CABGA256: 24,288 LUTs, 56 block RAMs, 28 DSPs**.
Hardware acceptance is pending; simulation passes alone do not establish a
working hardware emulator. The first acceptance ROM is the local diagnostic,
followed by the mGBA autorun suite and physical screen/button checks.

The latest mapped build on 2026-10-12 uses 47/56 block RAMs, 21/28 DSPs
and 23,772/24,288 logic sites, down from the initial 40,436 sites. Synthesis
checks and pack-only verification pass. The earlier mapping of the corrected
candidate uses 23,827 sites; its placement has completed and routing is running.
Both include the LCD recovery fix and soft mapping of single-user
synchronous resets; the earlier color-sharing map used 23,714 sites.
The earlier `bf8ace6` candidate completed routing at 24,107 logic sites,
43 block RAMs and 27 DSPs. Its final speed-grade-8 timing passes at all four
clock constraints (core maximum 32.62 MHz against 21 MHz). The routed
568,491-byte bitstream has been uploaded to the connected GreyMecha.
Hardware PSRAM initialization and boundary/alias readback pass. A warm
guest restart completes all eleven diagnostic checks (`0x7ff`), including
arithmetic, shifter and register-bank checks, and continues rendering frames.
All ten injected KEYINPUT bits, simultaneous L/R and release read back correctly.
The user confirms the physical button indicators respond after a guest
restart. Cold startup remains unreliable: other boots stall in the BIOS
after one captured frame. Reliable startup and the larger ROM suite remain
pending, so this is not yet a completed hardware deployment.
The LCD now acknowledges discarded partial-frame rows once per FIFO entry.
A startup regression queues partial rows ahead of frame zero: the original
display stalls; the corrected display passes all pixels in fitted/native
frames. This fix is not present in the first hardware bitstream and is being
built into a new candidate. The USB test runner keeps a persistent raw REPL
session because CircuitPython clears globals when entering raw mode again.
Separate synthesis of the core with the board's constant BIOS-write inputs
and unused audio/pixel-address outputs uses 20,388 LUT4s, 64 distributed RAM
blocks and 20,774 packed logic sites, plus 40 block RAMs and 21 DSPs.
This is above the 17K core estimate. Separate optimization means the core
and board section estimates do not form an exact additive partition.
The board shares DMA address adders and the CPU's
ADD/ADC/SUB/SBC datapath and ARM barrel shifter. Their arithmetic behavior
is exhaustively proved with Yosys SAT; the diagnostic also checks carry, borrow and
overflow flags after booting the open BIOS. Sprite priority/coverage
metadata now uses two block RAMs. The ARM general registers use distributed
RAM with native bank selection instead of copying banks through flip-flops.
Mutually exclusive instruction types share destination/block and
accumulator/Thumb-BL read ports without adding read latency.
The area mapping uses ABC's area objective without carry cells or wide LUTs.
`MIN_SRST_FANOUT=2` lowers single-user synchronous resets into their data
paths before flip-flop mapping. This avoids isolated ECP5 tile reset controls
and retains asynchronous reset behavior; `MIN_SRST_FANOUT=0` disables the
low-fanout policy for comparisons.
This includes the object-window RAM and block-RAM panel command ROM.
Host transfer counters and bounds arithmetic now use the validated 8 MiB
range; exhaustive SAT checks preserve the original packet validation and
legal counter updates. Sprite line settings also use block RAM, retaining
their original registered read latency.
The host's 256-byte write payload uses four block RAM byte banks instead
of distributed RAM. Word zero is prefetched during packet reception and
each subsequent word at PSRAM completion, preserving the issue cadence.
SPI/CRC tests cover full payloads followed by short packets and upper-address
readback. This change saves 220 logic sites in the complete mapped design.
Alpha blending, brightening and darkening share mutually exclusive color
products and a result register without changing pipeline latency. Exhaustive
SAT checks compare every color, effect and five-bit coefficient, including
coefficient saturation, with equations extracted from the original source.
This saves six DSPs and 173 logic sites in the complete mapped design.
The renderer reference instantiates an independent original compositor.
The 100 MHz core target placed but its estimated maximum was about 32 MHz.
The board now targets a nominal 20 MHz core with unchanged 80 MHz panel
and 50 MHz flash clocks. The internal oscillator makes these approximately
20.67/82.67/51.67 MHz; the LPF constrains them to 21/85/53 MHz.
Button counters use the core frequency bound. Flash and complete LCD-stream
simulations pass at these core/panel/flash clock ratios.
The build uses conservative speed-grade-6 timing; `FPGA_SPEED` and
`NEXTPNR_FLAGS` permit explicit tool overrides.
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
The renderer matches the original for 34,560 pixels with both on-chip and
variable-latency external low VRAM, covering all six modes, layers, sprites,
transforms, windows, mosaic, alpha blending, brightening, darkening and
coefficients 0, 1, 8, 16, 17 and 31. Semitransparent sprites remain present
in the brightness scenes to verify their alpha override.
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

Run physical tests from Windows with Python 3.7 or newer and pyserial:

```powershell
python tools/hardware_test.py --port COM9 --drive E:/ diagnostic
python tools/hardware_test.py --port COM9 --drive E:/ suite --minutes 60
```

The runner stages `/apps/gba`, uses the existing NVM loader and a full MCU
reset, programs and verifies the selected cartridge, checks PSRAM boundaries,
boots the BIOS and checks the ROM's SRAM report. It preserves root `code.py`.
The diagnostic additionally checks injected buttons; the suite exports its
CRC-checked result report. Logs and reports go under `build/hardware/`.
On a full badge filesystem, `--temporary-rom` backs up the device's GBA
bitstream locally, uses its space to install the test cartridge, then removes
the temporary ROM and restores the bitstream before launch. This path has
been exercised on the board; the restored bitstream's SHA256 matches.
For bring-up of the first candidate, `--retry-stalled-boot` explicitly logs
up to two warm guest restarts after an unchanged BIOS PC/frame count. A
successful retried test does not establish reliable cold startup.
`--resume` attaches the collector to a running guest without reprogramming
the FPGA, installing a cartridge or clearing guest RAM. Live suite progress
and completed-suite counters are saved to `build/hardware/suite-progress.json`.
Progress symbol addresses are used only for the verified ROM binary hash;
eight-bit test IDs in suites with more than 255 cases are marked ambiguous.
USB disconnects are recorded as interrupted runs, and cleanup preserves the
original transport error. The first suite attempt was interrupted by a
user-confirmed badge reset; a new run is progressing on the hardware.
The GBA host uses the distinct `gba_protocol` module so menu apps that have
already imported a different `protocol` module cannot change its wire format.
The GBA menu entry is added after actual hardware acceptance.
