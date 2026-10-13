# Current FPGA build handoff

This candidate retains the working 25 MHz image's memory layout. It adds
corrected LCD red/blue ordering, approximately 67 MHz QSPI cartridge reads,
and approximately 50 MHz SPI PSRAM reads (writes remain 25 MHz).
The core stays at approximately 20 MHz. The actual clocks scale with OSCG.

The BRAM-priority relocation under `rtl/bram_priority` is a separate
experiment, exceeds FPGA capacity, and is **not selected by this build**.
The saved 25 MHz bitstream is the hardware baseline. This new combined
candidate still requires resource, routing, timing and hardware acceptance.

## Build on another Linux computer or WSL

```bash
git clone --branch gba https://github.com/Hackin7/GreyMechaArmy_Tests.git
cd GreyMechaArmy_Tests
bash emulators/gba/tools/build_current.sh
```

Install GNU Make, Python 3, GHDL, Yosys with ECP5/ABC9 support,
nextpnr-ecp5 with the ECP5 chip database, and Project Trellis `ecppack`.
Icarus Verilog and `vvp` are needed for the RTL regressions.
The current machine uses GHDL 6.0.0, Yosys 0.65
(b85cad634782fafac275e5f540c056bfacb2b5d2), and nextpnr 0.10-5+b1.
Older tools may map the design differently. No GHDL Yosys plugin is required;
GHDL exports Verilog first. Vendored core sources are already in the repository.
ROMs and an ARM compiler are not needed to synthesize this FPGA image.

Generated core and synthesis checkpoints stay in
`/tmp/greymecha_gba_qspi67_psram50_colour`; set `GBA_BUILD_WORK` to override.
The build targets ECP5-25K, CABGA256, speed grade 6, placement seed 1.
Outputs under `emulators/gba/build/qspi67-psram50-colour`:

- `board-yosys.log`: synthesis and resource mapping.
- `board-nextpnr.log`: placement, routing and timing.
- `board-timing.json`: timing report.
- `gba.bit`: compressed bitstream, produced only after nextpnr succeeds.

Start from source on the other computer; a running router process cannot
be migrated by pushing Git. The current local build remains running.
Generated logs, checkpoints and new bitstreams are excluded from this commit.
Routing can take hours at this design's high utilization. Do not upload a
candidate until routing succeeds and all clock timing constraints pass.

## Checks

```bash
cd emulators/gba
make test-qspi-fast test-display
make test-psram test-host
```

The fast-QSPI and LCD regressions passed for this source, including 115,200
serialized pixels in each normal/partial-start LCD case. A dedicated PSRAM
burst test with a 100 MHz PHY, read divider 1, write divider 2 and falling-edge
read sampling also passed all byte masks, boundaries and reset recovery.
Separate controller hardware evidence is recorded in
`validation/flash-qspi-below79-2026-10-13.json` and
`validation/psram-speed-read51-final-2026-10-13.json`; it does not establish
acceptance of the combined full-emulator candidate.
