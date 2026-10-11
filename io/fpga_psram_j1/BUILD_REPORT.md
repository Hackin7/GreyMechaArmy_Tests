# Original SPI baseline build report

Generated on 2026-10-12 for the GreyMecha ECP5-25K, CABGA256, rebuilt for
the corrected wiring: IO0=A9, IO1=B10, IO2=B9, IO3=A8, SCLK=A3, CE#=A10.

| Item | Result |
| --- | --- |
| Preserved bitstream | `bitstreams/spi_12mhz.bit`, compressed |
| Size | 113,127 bytes |
| Nominal FPGA clock | OSCG DIV=6, 51.67 MHz |
| Nominal PSRAM clock | FPGA clock / 4, 12.92 MHz |
| Routed internal maximum frequency | 138.58 MHz; PASS at 51.67 MHz |
| Pre-pack LUT4 count, including carry LUTs | 814 / 24,288 |
| Flip-flops | 521 / 24,288 |
| Block RAM / DSP multipliers | 0 / 0 used |
| Simulation | PASS, 1,816 PSRAM transactions |
| Complete top-level wiring simulation | PASS, user's physical pins and QPI recovery |
| Strict Verilator lint | PASS, no warnings |
| Yosys `check -assert` | PASS, zero problems |
| Synthesized board-pin connectivity | PASS, dedicated host ports and PSRAM IO1 preserved |
| CircuitPython client | Syntax and response-decoding checks passed |
| Hardware upload / command bridge | PASS on connected GreyMecha, COM9 |
| PSRAM identification / memory verification | PASS: ID `0d 5d 53`, complete hardware script passed |

SHA-256:

```text
a61da7a9d75d5a63f8cf656cc2578384d13b3a8f633ff686e7e425c9a1a21e76
```

Toolchain: Yosys 0.65 (`b85cad634782fafac275e5f540c056bfacb2b5d2`),
nextpnr-ecp5 0.10-5+b1, Icarus Verilog 12.0, Verilator 5.048,
installed Project Trellis `ecppack`, run through WSL.

Simulation covers the complete command bridge and behavioral RAM model:
startup and cached ID, recovery from QPI mode, independent-address writes,
single-byte reads, 1 KiB boundary/top-of-memory access, passing 256-byte
tests, injected corruption with first-failure reporting, invalid addresses
and opcodes, partial frames, and button-triggered testing. The model also
checks CE# low <=8 us and high >=50 ns. It is not a vendor timing model.
The second simulation uses `top.v` and the user's physical-pin wiring,
checking QPI recovery across all four SIO pins, ID, memory writes/reads,
unused-pin release, button debounce and held-button suppression.

Yosys emits its generic limited-tristate-support warning for top-level
bidirectional pins. These are mapped to ECP5 I/O buffers during packing.
There are no undriven-signal/check failures. A separate netlist check now
verifies the host input/output ports survive synthesis as connected nets:
`check -assert` alone did not detect the original constant-Z host inputs.
ABC emits informational carry
network warnings. Neither simulation nor internal timing analysis establishes
electrical correctness on a physical board.

The prepared part is an **external APS6404L-3SQR at 3.3 V** with the J1 wiring
in [README.md](README.md). The public GreyMecha BOM lists W25Q128JVS flash;
this bitstream is not a controller for those onboard chips.

## Connected hardware results

The known badge GPIO probe returned `0xa4/0xa5` on GP8..15, verifying the
existing FPGA upload and RP2350 wiring. The initial demo had its host inputs
optimized away due to constant-Z assignments on a shared inout vector.
Using dedicated input/output ports fixed the command link; this regression
is covered by `scripts/check_netlist.py` during synthesis.

The initial pinout also had J1's two signal rows swapped. Correcting all six
assignments in the bitstream resolved identification and memory access.
The final bitstream uploaded 113,127 bytes in 163 ms and the complete
`scripts/device_test.py` run ended with `HARDWARE_TEST_PASS`:

- ID `0d 5d 53`, including the expected KGD `5d`.
- `Hello FPGA` written/read at `0x100`.
- Byte write/read at `0x3ff`, `0x400`, `0x400000`, and `0x7fffff`.
- Five FPGA 256-byte pattern tests at `0`, `0x3f0`, `0x10000`,
  `0x400000`, and `0x7fff00`; all passed.
- Distinct-address alias checks at zero, each of the 23 address bits, and
  the final byte; all writes performed before read verification.
- Data patterns `00`, `ff`, `55`, `aa`, and every walking-one bit.
- Reset/ID repeat and post-reset string write/read; passed.

This is not an exhaustive test of every byte in the 8 MiB device. The tests
verify representative regions, address/data lines and reset recovery at the
demo's nominal 12.9 MHz single-bit SPI clock.

Opcode 6 / `p.pins()` remains available for pad-level diagnostics. Earlier
debugging observed the expected 74 initialization edges and 40 byte-read
edges; the helper's activity flags/count accumulate since FPGA reset.

Evidence: `build/hardware_test.log` (final passing run). Earlier diagnostic
logs `build/memory_diag.log`, `build/byte_diag.log`, and `build/pin_diag.log`
were collected with the superseded row mapping and do not describe the
final bitstream. The deployed bitstream/client hashes match the
workspace files. The badge's root `code.py` hash remains unchanged, and
configuration used the existing volatile FPGA upload path.
