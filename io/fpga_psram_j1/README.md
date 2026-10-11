# GreyMecha J1 PSRAM test

This standalone Verilog design lets the ECP5-25K directly read and write an
**external 3.3 V APS6404L-3SQR SPI/QPI PSRAM (64 Mbit / 8 MiB)** on J1.
The FPGA generates every PSRAM transaction. The badge's RP2350 is only a
command bridge, accessed through its CircuitPython USB REPL.

The generated bitstream is [build/fpga_psram_j1.bit](build/fpga_psram_j1.bit).
The design includes initialization, cached ID reads, single-byte reads/writes,
a destructive 256-byte FPGA self-test, LED status and an interactive client.

## Hardware identification

The earlier `linux/BUILD_PICO2_LINUX.md` note identifying onboard APS6404L
PSRAM could not be substantiated: GreyMecha's published `prototype_3` BOM
lists **W25Q128JVS flash at U6/U9**, and the public main-branch PCB also lists
flash, without APS6404L. **Flash and PSRAM use different protocols. This
design targets an added APS6404L-3SQR, not either onboard flash chip.**

Sources checked:

- [GreyMecha published BOM](https://github.com/NUSGreyhats/greybadge25/releases/download/prototype_3/BOM-greybadge_pcb.csv)
- [GreyMecha PCB nets and connector pads](https://github.com/NUSGreyhats/greybadge25/blob/main/hardware/greybadge_pcb/greybadge_pcb.kicad_pcb)
- [APS6404L-3SQR datasheet, revision 2.7](https://www.apmemory.com/en/downloadFiles/032411212009597427)

APS6404L suffixes matter: a 1.8 V variant cannot use the following 3.3 V
connection. Check the full ordering code on the external module/chip.

## J1 wiring

**GreyMecha's J1 connector uses the numbering below; do not plug in a generic
PMOD RAM module assuming standard PMOD power-pin positions.** Locate PCB
pad 1 and check orientation against the board before connecting power.
Here, “J1 pad” means the physical KiCad connector pad number, while
`pmod_j1[n]` is the logical index used by the existing repo constraints.

| PSRAM signal | PSRAM SOIC/USON pin | J1 pad | FPGA pin | Verilog port |
| --- | ---: | ---: | --- | --- |
| VDD | 8 | 1 or 2 | supply | +3.3 V |
| VSS | 4 | 3 or 4 | ground | GND |
| CE# | 1 | 5 | A10 | `pmod_j1[0]` |
| SI / IO0 | 5 | 7 | A9 | `pmod_j1[1]` |
| SO / IO1 | 2 | 6 | B10 | `pmod_j1[4]` |
| SCLK | 6 | 11 | A3 | `pmod_j1[3]` |
| IO2 | 3 | 8 | B9 | `pmod_j1[5]` |
| IO3 | 7 | 9 | A8 | `pmod_j1[2]` |
| unused | — | 10 | B8 | `pmod_j1[6]` |
| unused | — | 12 | A4 | `pmod_j1[7]` |

This mapping incorporates the user's correction that J1's top and bottom
signal rows were swapped in the initial pinout. Reload the rebuilt bitstream
when changing from the earlier mapping.

Connect all six signal wires: IO2/IO3 are used to exit QPI mode during
initialization. Use short wires, a low-ESR 1 uF ceramic capacitor beside the RAM
(an optional 100 nF capacitor can supplement it),
and a CE# pull-up (for example 10 kOhm to 3.3 V) to keep it deselected before
FPGA configuration. Connect only the external chip/module to these signals;
do not connect a second active controller to the same PSRAM bus.

The public PCB connects J1's supply pads and its FPGA I/O bank supplies to
3.3 V. Consequently this design uses `LVCMOS33`, unlike older demos' reused
`LVCMOS25` settings. Verify the supply on your board revision before use.

## Load and interact

Create `/apps/psram_j1/` on the badge's CIRCUITPY drive and copy:

| Repo file | Badge destination |
| --- | --- |
| `build/fpga_psram_j1.bit` | `/apps/psram_j1/fpga_psram_j1.bit` |
| `badge/psram.py` | `/apps/psram_j1/psram.py` |
| `badge/run.py` | `/apps/psram_j1/run.py` |

Use Thonny's CircuitPython REPL. Stop the normal badge application first.
Run `/apps/psram_j1/run.py`, or enter:

```python
import sys
sys.path.append('/apps/psram_j1')
import psram
psram.load()
p = psram.Psram()
p.id()                         # vendor, KGD, density bytes; KGD should be 0x5d
p.status()
p.pins()                       # actual pad levels, activity and SCK edge count
p.write(0x100, b'Hello FPGA')
p.read(0x100, 10)               # b'Hello FPGA'
p.write(0x7fffff, b'\x5a')
p.read(0x7fffff)                # b'Z'
p.self_test(0)                 # overwrites and verifies bytes 0..255
p.self_test(0x7fff00)           # tests the final 256 bytes
p.address_test()               # checks data bits and 23 address bits; destructive
p.id(reset=True)               # reset chip, exit QPI, refresh cached ID
p.deinit()                     # release RP2350 command pins
```

Initialization waits about 0.4 ms. `ready=True` means the initialization
sequence finished; **`id_good=True`** means its KGD byte was actually 0x5d.
If ID reads as all zeros/ones or KGD is wrong, check power, wiring and the
exact chip part before trusting a memory test. The manufacturing/density
bytes may differ; the model's `0d 5d 26` is an example, not a required ID.

If the badge reports a GPIO “in use” error, the stopped menu may still own
its FPGA overlay. Release its `fpga_overlay` (including button mode),
`display_bus`, and `jtag_rst` objects from `hardware.hw_state` before loading,
or use a clean CircuitPython session that has not started the menu. The
sample doesn't replace your root `code.py` or firmware. Loading uses the
existing `hardware.fpga.upload_bitstream()` RAM configuration path; it
doesn't program configuration flash. Restart normal firmware to restore
the normal FPGA application.

## Standalone button / LEDs

After initialization, press **FPGA button 0 (B4)** once to run the 256-byte
test at address zero. Holding the button doesn't retrigger it. The separate
active-low reset button at C12 restarts the whole design and initialization.

| LED bit | Meaning when high |
| ---: | --- |
| 0 | Busy (initializing or executing a command/test) |
| 1 | Initialization finished |
| 2 | Last 256-byte self-test passed |
| 3 | Command/test error |
| 4 | ID KGD byte equals 0x5d |
| 5–7 | Unused |

A passed self-test is cleared by the next nonzero host command. Read
`p.status()` immediately afterwards to inspect it. On failure, the reply
contains the first failing address, actual byte and expected byte.

## Architecture and limits

```text
CircuitPython USB REPL
   -> RP2350 GP8/9/10/11, slow command SPI
   -> host_spi -> psram_demo -> psram_spi -> spi_transaction
   -> J1 -> external APS6404L
```

- `src/top.v`: ECP5 oscillator, reset, button debounce and physical pins.
- `src/host_spi.v`: synchronized host input, command framing, reply snapshot.
- `src/psram_demo.v`: commands, range checking, 256-byte self-test.
- `src/psram_spi.v`: power-up wait, QPI exit `F5`, reset `66/99`, ID `9F`,
  standard SPI read `03` and write `02`.
- `src/spi_transaction.v`: mode-0 clock/data shifting and CE# spacing.

OSCG DIV=6 has nominal 51.67 MHz frequency; the RAM clock divides it by four,
giving about **12.9 MHz SPI**. Oscillator tolerance affects actual speed.
Single-byte read/write transfers are 40 SPI clocks. Initialization's ID
transfer is 56 clocks. CE# has eight system cycles of hold time and at least
eight cycles of high spacing. Even the longest transfer is about 4.5 us,
below the datasheet's 8 us maximum selected interval; CE# is never held low
while waiting for RP2350/USB commands. The startup wait exceeds 150 us.

This is a bring-up design: data reads/writes use **single-bit SPI and one
byte per transaction**, not burst/QPI bandwidth. Python's bit-banged command
bridge is deliberately slow; it doesn't indicate achievable FPGA memory
throughput. The FPGA self-test runs without per-byte host traffic. The
256-byte test checks a local region; `address_test()` separately checks
address aliasing. Neither is a full exhaustive 8 MiB memory test.

## Host protocol

Host SPI mode 0, MSB first, SCK <= 1 MHz. Allow >=1 us after CE# falls before
the first clock and >=1 us between transactions for synchronization.
Send a five-byte command with CE# low, release CE#, then poll the eight-byte
reply in a separate transaction (transmit zeros). Byte zero opcode is a
no-op, allowing polls without disturbing an executing operation. Wait for
busy to clear before sending another operation.

The host return line is a dedicated, continuously driven output on B16
(RP2350 GP10). Keep GP10 configured as an input. SCK/MOSI/CE# use explicit
FPGA input ports on A15/B15/C15 to preserve them through synthesis.

Command: `[opcode, address_hi, address_mid, address_lo, write_data]`.

| Opcode | Action |
| ---: | --- |
| 0 | No-op / status poll |
| 1 | Read byte |
| 2 | Write byte |
| 3 | Reinitialize / reset and read ID |
| 4 | Write/read 256 bytes starting at address |
| 5 | Return cached ID |
| 6 | Return pad levels, accumulated activity and SCK rising-edge count |

Reply: `[0x50, flags, actual_data, expected_data, result_hi, result_mid,
result_lo, error_code]`. Flags bits 0..4 are busy, ready, self-test pass,
error, ID-good. Result is the operation/test address, or the three ID bytes
for opcodes 3/5. Errors: 0=none, 1=initializing/busy, 2=unknown opcode,
3=out-of-range, 4=test mismatch. Commands received while a requested
operation/test is running are ignored; replies remain available. Partial
command frames are discarded when CE# rises.

For opcode 6, `actual_data[5:0]` is `{CE#, SCK, IO3, IO2, IO1, IO0}`.
`expected_data[7:0]` contains activity flags in this order, low bit first:
CE low/high, SCK low/high while selected, IO0 low/high while selected,
IO1 low/high while selected and its FPGA driver disabled. Result is the
24-bit SCK rising-edge count observed while selected. Both flags and count
accumulate since FPGA reset; normal initialization produces 74 edges and
a byte read/write adds 40. These observe FPGA pad inputs and do not prove
continuity between the board header and the external memory package.

## Build and verification

Requires Yosys with ECP5 support, nextpnr-ecp5, Project Trellis/ecppack,
Icarus Verilog, and Verilator. From this directory in Linux/WSL:

```sh
make test lint all
```

Build logs, configuration, bitstream and SVF are in `build/` (ignored by Git).
`make test` exercises a behavioral APS6404L model and the complete command
transport. It checks ID framing, QPI recovery, reads/writes at the top and
at a 1 KiB boundary, successful self-tests, injected read corruption,
invalid opcodes/addresses, truncated commands, button triggering, and CE#
timing. A second simulation instantiates the complete `top.v` with the
user's physical-pin wiring and checks QPI recovery, ID, unused-pin release,
button debounce, memory testing and held-button suppression. `make lint`
treats warnings as errors. Synthesis runs `check -assert` and a separate
board-pin connectivity check to catch optimized-away host inputs.

**Connected-badge hardware tests passed on 2026-10-12 with the corrected
J1 row mapping.** The PSRAM returned ID `0d 5d 53`. String write/read,
1 KiB boundary and final-byte access, five 256-byte FPGA self-tests,
address/data-line tests, reset/ID and post-reset read/write all passed.
This checks representative regions and all address bits rather than every
byte of the 8 MiB device.

`scripts/repl_run.py` can run `scripts/device_test.py` through COM9 once the
three app files are copied. It checks ID before executing destructive
string, boundary, five-region FPGA self-test and address/data tests.
`scripts/device_memory_diag.py` performs only reset/ID and read-only checks.
Logs are saved in `build/`. The existing root `code.py` is preserved.

See [BUILD_REPORT.md](BUILD_REPORT.md) for the generated artifact's results.
