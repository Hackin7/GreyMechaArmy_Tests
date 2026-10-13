# Priority RAM allocation experiment

The requested full banks are BIOS (16 KiB), IWRAM (32 KiB), and lower VRAM
(64 KiB). `gba_local_mem.sv` stores them in 8 + 16 + 32 ECP5 EBRs. Existing
loader byte addresses are retained. EWRAM and save memory remain in PSRAM.
Upper VRAM moves to PSRAM at `0x110000`; a clock-stop adapter preserves its
synchronous CPU/sprite/bitmap interfaces. Other board logic keeps running.
Requests and emitted pixels are qualified by the logical clock step, and
responses are held across a stopped emulator clock.

## PSRAM relocation and colour correction

The current generator moves OAM, both palettes, four background colour
line buffers, sprite colour/settings, priority metadata and object-window
bits to PSRAM. These eleven clients
use separate 4 KiB regions beginning at `0x140000`. Only three cached words
per client remain local, preserving synchronous read timing and coherent
byte writes. Arbitration queues request flags, not copies of RAM payloads.

The LCD scanline payload also moves to PSRAM, beginning at `0x200000`.
The renderer waits for pixel writes to commit. A complete line is published
only after its final write finishes. Panel output pauses on a read miss;
its one-word cache includes the ring epoch to distinguish reused slots.
The duplicate 512-byte core ROM cache is replaced by paired-word transport
registers; cartridge locality is supplied by the QSPI frontend cache.
USB packet staging uses `0x180000..0x1800FF`; completed readback payloads
use `0x180100..0x1801FF`. Uploads modify their destination only after CRC
validation. Two reply words are prefetched locally to meet host SPI timing.

Palette **colour ordering** is corrected in `gba_display.v`: RGB565 is sent
without the second red/blue swap. This correction is included in the
relocation source and has not yet been uploaded to the board.

Validation so far:

- OAM/palette/rendering-line relocation: 34,560 reference pixels match across
  all modes, sprites, windows, mosaic, alpha and brightness effects.
- Open BIOS and all eleven diagnostic checks pass with those graphics
  memories externalized; pause and key input also pass.
- PSRAM LCD storage: 115,200 serialized pixels match in each of normal and
  partial-frame startup runs, including both viewports and colour ordering.
- Scratch arbitration passes simultaneous requests from all fourteen clients
  and byte masks.
- PSRAM USB buffering passes real SPI framing at two clock rates, including
  256-byte replies, save packing, status polling and CRC destination protection.
- The final graphics configuration, including PSRAM sprite priority and
  object-window bits, matches all 34,560 reference pixels as well.

The intermediate graphics-only mapping uses **30,908/24,288 logic sites,
56/56 EBRs and 22/28 DSPs**. It does not include the subsequent PSRAM LCD
storage, ROM-cache reduction or narrower arbiter indices. The combined
mapping measures **26,916/24,288 sites, 56 EBRs and 21 DSPs**, before the
last reset-rearm correction. That saves 6,818 sites versus the earlier
33,734-site priority-RAM variant, but still exceeds capacity by 2,628.
The reset-aware renderer comparison and full eleven-check diagnostic both
pass. This variant is not ready for deployment.

The generator now includes USB buffers, sprite priority metadata and
object-window bits in the PSRAM relocation. All bulk relocation is connected;
remaining work is logic reduction, final resource mapping, timing and hardware
acceptance, rather than moving the other payloads back into local SRAM.
Architectural CPU registers, cache words, request flags and constant lookup
logic remain FPGA state rather than external RAM payloads.

The upper-VRAM graphics port has two cached words: a single word thrashes
between the alternating sprite and bitmap fetchers even while their addresses
are unchanged. CPU writes update matching entries. This is independent of
the existing four-word lower-VRAM fetch cache.

## Reproduce

The current priority build selects width-specialized cache words, a
priority-mask round-robin arbiter, shared CPU shift/accumulator reads and
wide-LUT mapping without carry chains. The measured cost is **26,415 logic
sites**, still **2,127 over capacity**. These changes do not add instruction
stages or alter the memory allocation. Instruction tests include register
shifts, MLA/UMLAL, Thumb BL and all register banks. The renderer comparison
still produces 34,560 identical pixels at the same simulated finish time.

| Experiment | Packed logic sites |
|---|---:|
| Earlier full relocation | 26,916 |
| Narrow words + priority-mask arbiter | 26,707 |
| Above with carry chains | 27,924 |
| Above with wide LUTs | 26,552 |
| Above with carry chains and wide LUTs | 27,881 |
| Wide LUTs + shared CPU shift-read port | **26,415** |

The arbiter alone decreases from 968 to 789 LUT4s with its grant order
unchanged under full and sparse request batches. Removing pending PSRAM
descriptor copies decreases 646 to 476 FFs, but increases 597 to 599 LUT4s
in its isolated mapping. `STABLE_CLIENTS` therefore remains an optional,
tested experiment and is **not enabled** in this variant. The normal PSRAM
controller retains descriptor snapshots and its prior request semantics.

For comparison, disable CPU sharing with `--no-shared-shift-read`, and
disable wide LUTs with `--no-wide-luts`. Mapping alternatives can resume the
same `pre_gates.il` checkpoint using `--resume`; carry mapping uses `--carry`.
None of these resource checks establishes routed timing or hardware FPS.

From `emulators/gba` in WSL/Linux:

```sh
make test-priority-memory
make test-priority-psram
make bram-priority-core
python3 tools/test_bram_priority_core.py
python3 tools/test_bram_priority_renderer.py
make bram-priority-map
```

Work is isolated in `/tmp/greymecha_gba_bram_priority`; normal generated RTL
and the saved working bitstreams are preserved. Both the normal board build
and this variant select approximately **67 MHz flash QSPI**, two PHY clocks per SCK
cycle, with PLL dividers 26/4. With the specified 310 MHz OSCG +/-15% range,
SCK is 67.1667 MHz nominal and at most 77.2417 MHz, below 79 MHz. The fast PHY
has a 155 MHz timing constraint. The earlier 28/4 controller test passed at
71.94635 MHz on this board, but could exceed 79 MHz at the oscillator limit.
The new divider passed the read-only hardware controller test at 66.80765 MHz,
with 17,664 bytes verified and 11.99 MB/s cache service throughput. The full
emulator with relocated RAM has not been deployed. PSRAM remains nominal 25 MHz SPI.

## Validation and limits

The direct and packed banks are tested at every logical address, with all
16 byte masks at every packing offset, adjacent-word preservation, and
simultaneous CPU/video/host requests. The upper-VRAM adapter is tested with
variable memory latency, cache aliases, writes, and reset. The full core
passes the open-BIOS diagnostic, all eleven flags, pause and injected keys.
The renderer matches 34,560 reference pixels across all display modes,
sprites, transforms, mosaic, windows, and blending effects.

This allocation is **not yet a deployable 25K design**. An initial mapped
variant needed approximately 33.7K logic sites and 58 EBRs: host readback and
LCD pixels were still inferred into EBRs. Generation now explicitly forces
those two buffers into distributed RAM, giving the three hot banks exclusive
use of all 56 EBRs. This cannot solve the logic overflow and increases its
LUT cost. Do not route or upload it as though it fits.

The smaller LCD FIFO (two slots) preserves one slot for an in-flight row and
passes 115,200 pixel checks, including partial-frame startup. With distributed
storage it packs to 1,477 sites rather than 2,709, saving 1,232. Shared debounce
uses one stable-vector timer: 104 LUT4s / 70 FFs instead of 283 / 165. A bounce
on one switch delays acceptance of the entire vector; the qualification
interval and button/chord behavior remain intact. The normal build retains
independent debounce and four scanline slots.

## Packing experiment

`gba_local_mem_packed.sv` packs eight words into seven 36-bit words plus a
four-bit spill. Its single read/write physical ports use read/modify/write
to preserve neighbors. The inferred cost is **51 EBRs, 1,636 LUT4s, 498 FFs**,
versus **56 EBRs, 166 LUT4s, 105 FFs** for direct byte banking (the direct
measurement used standard carry/wide-LUT mapping). Five freed EBRs come at a
substantial logic and latency cost. It is tested but **not selected** by the
board fabric. The theoretical 50-EBR payload does not match the tool's actual
18-bit read-mode packing; use the measured count.

The earlier architectural reductions targeted duplicated palette/OAM
read ports and graphics line buffers. The trial netlist uses 512 distributed
RAM primitives just for palettes/OAM and 320 for the five color line buffers,
before their read multiplexers. Sharing their physical read ports, exploiting
the shared background engine, or moving line storage behind a bounded
scratch-memory interface can save substantially more than trimming controls.
Those changes need timing/behavior comparisons; the requested full hot-bank
placement cannot be treated as a drop-in swap on this FPGA.

Oscillator reference: [Lattice SED/SEC guide, section 4.1](https://www.latticesemi.com/view_document?document_id=32323).
