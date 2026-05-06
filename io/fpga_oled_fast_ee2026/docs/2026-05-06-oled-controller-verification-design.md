# OLED Controller Verification — Design

**Date:** 2026-05-06
**Status:** Approved (brainstorming complete, ready for implementation plan)
**Working dir:** `io/fpga_oled_fast/`

## 1. Problem

The OLED panel does not light up after flashing the new streaming bitstream — even at 5 MHz SCLK (which the original `fpga_oled` design ran reliably). LED[7] (`init_done`) does turn on, so the init FSM thinks it has completed all 182 ROM bytes plus the 11-byte window setup. But there is **no end-to-end verification** that the SPI bytes actually emitted on the wire match the GC9A01-required init sequence, or that the streamed pixel words have correct bit ordering.

So far we have only verified:
- Yosys synthesis (syntax, primitive inference)
- nextpnr-ecp5 timing closure (passes at both 5 MHz and 75 MHz targets)
- Hardware behavior (OLED stays dark)

Gaps:
- No simulation of `oled_init.v` or `oled_stream.v`
- No bit-level inspection of SCLK / MOSI / CS / DC sequencing
- No comparison against the known-good init sequence in `scripts/gen_gc9a01_init_rom.py`

## 2. Goal

Add **iverilog testbenches** for `oled_init.v` and `oled_stream.v` that print the SPI byte / pixel-word sequence to stdout. Eyeball the output against the expected sequence to identify which module is producing wrong output. Once the bug is identified and fixed, the testbenches stay around as a re-runnable sanity check.

## 3. Non-goals

- Not a self-checking regression suite (out of scope; can evolve later if needed).
- Not a full GC9A01 behavioral panel model (out of scope).
- Not a simulation of OSCG / EHXPLLL / ODDRX1F primitives (probes internal signals, not pin-level ODDR output — the ODDR is the one significant gap).

## 4. Tooling

WSL has the full open-source ECP5 toolchain plus simulation tools:
- `iverilog` — Verilog → vvp compiler
- `vvp` — virtual machine to run the compiled simulation
- `gtkwave` — waveform viewer (optional, for VCD inspection)

All four already verified present at `/usr/bin/`.

## 5. Architecture

Two unit-test testbenches under a new `tb/` directory:

```
io/fpga_oled_fast/
├── src/                   (existing RTL)
├── tb/                    (NEW)
│   ├── tb_oled_init.v     (NEW — drives oled_init standalone)
│   ├── tb_oled_stream.v   (NEW — drives oled_stream standalone)
│   └── build/             (NEW — .vvp and .vcd outputs, gitignored)
├── Makefile               (modified — add sim_init, sim_stream targets)
└── ...
```

Each testbench is self-contained: clock generator, reset sequencer, SPI-byte (or 16-bit-pixel) sniffer, watchdog timer, VCD dump.

## 6. `tb_oled_init.v` — init-path verification

### Driver

```verilog
reg clk = 0;
always #5 clk = ~clk;            // 100 MHz simulated

reg resetn = 0;
initial #100 resetn = 1;          // release reset after 100 ns

reg rearm = 0;

// CLK_HZ shrunk so RST_LO_CYCLES, WAIT10_CYCLES, and the SLPOUT pause
// are tiny in simulation time. SPI_CLK_DIV=1 makes SCLK fast (50 MHz
// in sim) so each byte takes ~32 ns to shift. Whole init in <100 us sim.
oled_init #(.CLK_HZ(100_000), .SPI_CLK_DIV(8'd1)) dut (
    .clk(clk), .resetn(resetn),
    .init_done(init_done), .ramwr_pulse(ramwr_pulse), .rearm(rearm),
    .sclk(sclk), .mosi(mosi), .dc(dc), .cs(cs), .rst_n(rst_n)
);
```

But: `oled_init` includes `gc9a01_init_rom.vh` which has 182 entries with absolute pause cycle counts (currently regenerated for `CLK_HZ=5_000_000`). At sim `CLK_HZ=100_000`, the SLPOUT pause is `9_000_000 / 5_000_000 * 100_000 = 180_000` cycles — wait, no: pause counts are absolute cycle values, not proportional to CLK_HZ. The ROM has `pause = 9_000_000` for SLPOUT regardless of param. At 100 MHz sim clock, that's 90 ms of sim time → ~90M cycles. Way too long.

**Fix:** Re-regenerate the ROM at a sim-friendly `CLK_HZ` for the simulation run, OR have the testbench skip the pause states. Cleanest: regenerate ROM in a "sim mode" that produces tiny pause values, then restore. **Simpler:** make the testbench `force pause_cnt = 4'd1;` whenever the FSM enters `S_INIT_PAUSE` so pauses elapse in 1 cycle. Cleanest of all: just regenerate the ROM at `CLK_HZ=10_000` before running the sim (script edit + run).

Decision: testbench `force` overrides — keeps the production ROM untouched. Specifically:

```verilog
// Skip init-ROM pauses so simulation completes quickly. The actual pause
// length doesn't affect SPI byte correctness, just timing between bytes.
always @(*)
    if (dut.st == 4'd6 /* S_INIT_PAUSE */)
        force dut.pause_cnt = 24'd1;
    else
        release dut.pause_cnt;
```

### SPI byte sniffer

```verilog
reg sclk_d = 0;
always @(posedge clk) sclk_d <= sclk;
wire sclk_rising = sclk & ~sclk_d;

reg [7:0] byte_buf = 0;
reg [3:0] bit_cnt  = 0;

always @(posedge clk) begin
    if (cs) begin
        bit_cnt <= 0;            // reset on CS deassert
    end else if (sclk_rising) begin
        byte_buf <= {byte_buf[6:0], mosi};
        if (bit_cnt == 7) begin
            $display("[%6t] %s 0x%02h", $time, dc ? "DAT" : "CMD",
                     {byte_buf[6:0], mosi});
            bit_cnt <= 0;
        end else begin
            bit_cnt <= bit_cnt + 1;
        end
    end
end
```

### Top-level test flow

```verilog
initial begin
    $dumpfile("tb/build/init.vcd");
    $dumpvars(0, tb_oled_init);

    wait (init_done);
    $display("[%6t] === INIT DONE ===", $time);

    #1000;
    rearm = 1;
    wait (ramwr_pulse);
    $display("[%6t] === RAMWR PULSE on rearm ===", $time);
    rearm = 0;

    #1000;
    $finish;
end

initial begin
    #50_000_000;                 // 50 ms watchdog
    $display("[%6t] === WATCHDOG TIMEOUT ===", $time);
    $finish;
end
```

### Expected output (excerpt)

```
[   500] CMD 0xEF
[   650] CMD 0xEB
[   800] DAT 0x14
[   950] CMD 0xFE
...
[ XXXXX] CMD 0x2A
[ XXXXX] DAT 0x00
[ XXXXX] DAT 0x00
[ XXXXX] DAT 0x00
[ XXXXX] DAT 0xEF
[ XXXXX] CMD 0x2B
[ XXXXX] DAT 0x00
[ XXXXX] DAT 0x00
[ XXXXX] DAT 0x00
[ XXXXX] DAT 0xEF
[ XXXXX] CMD 0x2C
[ XXXXX] === INIT DONE ===
[ XXXXX] CMD 0x2C
[ XXXXX] === RAMWR PULSE on rearm ===
```

Manual verification: open `scripts/gen_gc9a01_init_rom.py`, scroll the `wr_cmd / wr_data` calls, compare against `CMD/DAT` lines from the dump. Any mismatch → bug.

## 7. `tb_oled_stream.v` — pixel-stream verification

### Driver

```verilog
reg clk = 0;
always #5 clk = ~clk;            // 100 MHz simulated

reg resetn = 0;
reg enable = 0;
initial begin
    #100 resetn = 1;
    #100 enable = 1;
end

wire [15:0] pixel_index;
reg  [15:0] pixel_data;

// Synthetic BRAM stand-in: pixel_data follows pixel_index by one cycle,
// so emitted pixel N should have value N.
always @(posedge clk) pixel_data <= pixel_index;

oled_stream dut (
    .clk(clk), .resetn(resetn), .enable(enable),
    .pixel_index(pixel_index), .pixel_data(pixel_data),
    .sclk_active(sclk_active), .mosi(mosi),
    .cs(cs), .dc(dc), .frame_done(frame_done)
);
```

### Pixel sniffer

The streamer emits one bit per `clk` cycle while `sclk_active && !cs`. Accumulate 16 bits, print as a hex word with the bit-order MSB-first matching the streamer's intent.

```verilog
reg [15:0] word_buf = 0;
reg [4:0]  word_bit_cnt = 0;
integer    pixel_print_count = 0;

always @(posedge clk) begin
    if (sclk_active && !cs) begin
        word_buf <= {word_buf[14:0], mosi};
        if (word_bit_cnt == 15) begin
            $display("[%6t] PIX %0d: 0x%04h",
                     $time, pixel_print_count, {word_buf[14:0], mosi});
            pixel_print_count <= pixel_print_count + 1;
            word_bit_cnt <= 0;
        end else begin
            word_bit_cnt <= word_bit_cnt + 1;
        end
    end
end

initial begin
    $dumpfile("tb/build/stream.vcd");
    $dumpvars(0, tb_oled_stream);
    wait (enable);
    #2000;                       // ~125 pixels
    $display("[%6t] === STOPPING (sniffed %0d pixels) ===",
             $time, pixel_print_count);
    $finish;
end
```

### Expected output

```
[   200] PIX 0: 0x0000
[   400] PIX 1: 0x0001
[   600] PIX 2: 0x0002
[   800] PIX 3: 0x0003
[  1000] PIX 4: 0x0004
...
```

### Failure interpretations

| Observed | Diagnosis |
|---|---|
| `PIX 0: 0x0001` (off-by-one early) | First pixel mis-loaded; non-streaming → streaming transition wrong |
| `PIX 1: 0x0000`, `PIX 2: 0x0001` (off-by-one late) | First word ate a stale bit before pixel[0]'s real MSB |
| `PIX 0: 0x8000` instead of `0x0001` | LSB streamed first (bit order reversed) |
| `PIX 0: 0x0100` instead of `0x0001` | Byte-swapped within pixel (LSByte first) |
| `PIX 0,1,2 = 0x0000, 0x0000, 0x0001` | Pre-fetch advances pixel_index too late |
| Stops after 1 pixel without `frame_done` | Reload boundary broken |

## 8. Build & run

### Makefile targets

```makefile
SIM_DIR = tb/build

$(SIM_DIR):
	mkdir -p $@

sim_init: $(SIM_DIR)
	iverilog -o $(SIM_DIR)/sim_init.vvp tb/tb_oled_init.v src/oled_init.v
	cd tb && vvp build/sim_init.vvp

sim_stream: $(SIM_DIR)
	iverilog -o $(SIM_DIR)/sim_stream.vvp tb/tb_oled_stream.v src/oled_stream.v
	cd tb && vvp build/sim_stream.vvp

sim: sim_init sim_stream

.PHONY: sim sim_init sim_stream
```

`cd tb` before `vvp` so `tb/build/init.vcd` and `tb/build/stream.vcd` (relative paths in the testbench `$dumpfile` calls) land in the right place.

### Output artifacts (gitignored)

- `tb/build/sim_init.vvp`, `tb/build/sim_stream.vvp` — compiled simulations
- `tb/build/init.vcd`, `tb/build/stream.vcd` — waveforms for gtkwave

## 9. What this verification does NOT cover

- **ODDR pin-level behavior.** Both testbenches probe the streamer/init outputs *before* the ODDR. If init bytes and pixel words are both correct in sim but the OLED is still dark, the prime suspect becomes the ODDR phase / mux / pin. A future `tb_top.v` with behavioral models for OSCG, EHXPLLL, and ODDRX1F would close this gap.
- **Top-level integration** (sequencer FSM, button mux, pin arbiter) — implicit, not directly tested.
- **Real GC9A01 panel timing requirements** (setup/hold, max SCLK frequency on the actual silicon).

The first gap is the biggest. If sim passes both TBs cleanly, the next step is either ODDR-aware sim or hardware probing (oscilloscope on SCLK / MOSI / CS / DC pins).

## 10. Out of scope

- Self-checking assertion-based regression suite.
- Behavioral model of GC9A01 panel internals.
- Continuous integration hookup.
- Simulation of OSCG, EHXPLLL, ODDRX1F primitives.
