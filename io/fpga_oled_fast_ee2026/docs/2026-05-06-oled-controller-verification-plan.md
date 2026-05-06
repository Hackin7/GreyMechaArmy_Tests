# OLED Controller Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add iverilog testbenches for `oled_init.v` and `oled_stream.v` that print SPI byte / pixel-word sequences, so we can identify where the streaming bitstream is producing wrong output.

**Architecture:** Two standalone testbenches under `tb/`. Each instantiates one DUT, drives clk/resetn/inputs, sniffs the output signals, prints decoded bytes/pixels via `$display`. Built and run via new Makefile targets `sim_init` and `sim_stream`.

**Tech Stack:** Verilog, iverilog (compiler), vvp (simulator), gtkwave (optional waveform viewer). All available in WSL.

**Reference spec:** `docs/2026-05-06-oled-controller-verification-design.md` in this same directory.

**Working directory for all paths below:** `C:/Users/zunmun/Documents/Stuff/Github/PERSONAL PROJECTS/GreyMechaArmy_Tests/io/fpga_oled_fast/`

---

## Notes on testing strategy

This is a debug verification plan. Each "test" here is a Verilog testbench that prints to stdout. There is no assertion-based pass/fail — verification is by eyeballing the dump against the expected sequence in `scripts/gen_gc9a01_init_rom.py` (for init) and the synthetic `pixel_data = pixel_index` pattern (for stream).

After running both testbenches, the analysis task identifies the divergence point (if any) and reports the suspected bug.

---

### Task 1: Create `tb/` directory and Makefile targets

**Files:**
- Create: `tb/build/.gitkeep` (just to anchor the dir)
- Modify: `Makefile`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p tb/build
touch tb/build/.gitkeep
```

- [ ] **Step 2: Add Makefile targets**

Append to `Makefile` (after the existing `clean` target, before `.PHONY`):

```makefile
SIM_DIR = tb/build

$(SIM_DIR):
	mkdir -p $@

sim_init: | $(SIM_DIR)
	iverilog -o $(SIM_DIR)/sim_init.vvp -I src tb/tb_oled_init.v src/oled_init.v
	cd tb && vvp build/sim_init.vvp

sim_stream: | $(SIM_DIR)
	iverilog -o $(SIM_DIR)/sim_stream.vvp -I src tb/tb_oled_stream.v src/oled_stream.v
	cd tb && vvp build/sim_stream.vvp

sim: sim_init sim_stream
```

Update the `.PHONY` line to include the new targets:

Replace:
```makefile
.PHONY: all bit clean
```

With:
```makefile
.PHONY: all bit clean sim sim_init sim_stream
```

- [ ] **Step 3: Sanity-check the Makefile parses**

```bash
wsl bash -lc "cd '/mnt/c/Users/zunmun/Documents/Stuff/Github/PERSONAL PROJECTS/GreyMechaArmy_Tests/io/fpga_oled_fast' && make -n sim_init"
```

Expected: prints (does not run) the iverilog and vvp commands. No "missing separator" or "no rule" errors. The testbench file `tb/tb_oled_init.v` doesn't exist yet, but `make -n` doesn't care.

---

### Task 2: Write `tb/tb_oled_init.v`

**Files:**
- Create: `tb/tb_oled_init.v`

- [ ] **Step 1: Write the complete testbench**

```verilog
// tb_oled_init.v — drives oled_init standalone, sniffs the SPI bytes it
// emits, prints them with CMD/DAT classification. Manual verification:
// compare the dump against scripts/gen_gc9a01_init_rom.py.
//
// CLK_HZ shrunk to 100_000 so the RST_LO and WAIT10 timers expire fast
// in simulation. SPI_CLK_DIV=1 makes SCLK 50 MHz in sim time → each byte
// takes ~32 ns to shift. The init-ROM pause states are skipped via a
// `force` override on pause_cnt so the SLPOUT 9_000_000-cycle wait doesn't
// dominate sim time.

`timescale 1ns / 1ps

module tb_oled_init;
    reg clk = 1'b0;
    always #5 clk = ~clk;            // 100 MHz simulated

    reg resetn = 1'b0;
    initial #100 resetn = 1'b1;

    reg rearm = 1'b0;

    wire init_done, ramwr_pulse;
    wire sclk, mosi, dc, cs, rst_n;

    oled_init #(.CLK_HZ(100_000), .SPI_CLK_DIV(8'd1)) dut (
        .clk         (clk),
        .resetn      (resetn),
        .init_done   (init_done),
        .ramwr_pulse (ramwr_pulse),
        .rearm       (rearm),
        .sclk        (sclk),
        .mosi        (mosi),
        .dc          (dc),
        .cs          (cs),
        .rst_n       (rst_n)
    );

    // Skip init-ROM pauses (SLPOUT, etc.) so simulation completes quickly.
    // Pauses don't affect SPI byte correctness — only timing between bytes.
    // S_INIT_PAUSE = 4'd6 in oled_init.v.
    always @(*) begin
        if (dut.st == 4'd6)
            force dut.pause_cnt = 24'd1;
        else
            release dut.pause_cnt;
    end

    // SPI byte sniffer: detect rising sclk while !cs, capture mosi into a
    // shift register; on every 8th bit, print the assembled byte with the
    // dc level (CMD vs DAT). Reset the bit counter on cs deassert.
    reg sclk_d = 1'b0;
    always @(posedge clk) sclk_d <= sclk;
    wire sclk_rising = sclk & ~sclk_d;

    reg [7:0] byte_buf = 8'd0;
    reg [3:0] bit_cnt  = 4'd0;

    integer byte_count = 0;

    always @(posedge clk) begin
        if (cs) begin
            bit_cnt <= 4'd0;
        end else if (sclk_rising) begin
            if (bit_cnt == 4'd7) begin
                $display("[%6t] %s 0x%02h", $time,
                         dc ? "DAT" : "CMD",
                         {byte_buf[6:0], mosi});
                byte_count <= byte_count + 1;
                bit_cnt <= 4'd0;
            end else begin
                byte_buf <= {byte_buf[6:0], mosi};
                bit_cnt <= bit_cnt + 4'd1;
            end
        end
    end

    // Top-level test flow
    initial begin
        $dumpfile("build/init.vcd");
        $dumpvars(0, tb_oled_init);

        wait (init_done);
        $display("[%6t] === INIT DONE (%0d bytes sent) ===",
                 $time, byte_count);

        // Test rearm
        #1000;
        rearm = 1'b1;
        wait (ramwr_pulse);
        $display("[%6t] === RAMWR PULSE on rearm ===", $time);
        rearm = 1'b0;

        #1000;
        $finish;
    end

    // Watchdog
    initial begin
        #50_000_000;
        $display("[%6t] === WATCHDOG TIMEOUT (sent %0d bytes) ===",
                 $time, byte_count);
        $finish;
    end
endmodule
```

---

### Task 3: Run `sim_init` and capture output

**Files:**
- Reads: `tb/tb_oled_init.v`, `src/oled_init.v`, `src/gc9a01_init_rom.vh`
- Writes: `tb/build/sim_init.vvp`, `tb/build/init.vcd`

- [ ] **Step 1: Run the simulation**

```bash
wsl bash -lc "cd '/mnt/c/Users/zunmun/Documents/Stuff/Github/PERSONAL PROJECTS/GreyMechaArmy_Tests/io/fpga_oled_fast' && make sim_init 2>&1 | tee tb/build/sim_init.out"
```

Expected: iverilog compiles without errors, vvp runs and produces ~193 lines of `[time] CMD/DAT 0xXX` output, then `=== INIT DONE (193 bytes sent) ===` (182 init ROM bytes + 11 window-setup bytes), then `=== RAMWR PULSE on rearm ===`, then `$finish`.

If iverilog reports `error: Unknown module type` for `OSCG`, `EHXPLLL`, or `ODDRX1F`, those are referenced from `src/oled_init.v` indirectly — they shouldn't be. Check the include order; `oled_init.v` should not pull in any pin-level primitives.

- [ ] **Step 2: Verify byte count**

```bash
wsl bash -lc "grep -c 'CMD\|DAT' tb/build/sim_init.out"
```

Expected: `193`. If different, init is sending the wrong number of bytes — that's a bug.

- [ ] **Step 3: Compare against expected init sequence**

The first 6 init bytes per `scripts/gen_gc9a01_init_rom.py` are:
```
CMD 0xEF
CMD 0xEB
DAT 0x14
CMD 0xFE
CMD 0xEF
CMD 0xEB
```

Verify the first 6 sniffed bytes match:

```bash
wsl bash -lc "grep -E 'CMD|DAT' tb/build/sim_init.out | head -6"
```

Expected: lines reading exactly `CMD 0xEF`, `CMD 0xEB`, `DAT 0x14`, `CMD 0xFE`, `CMD 0xEF`, `CMD 0xEB` (with timestamps prefixed).

The last 12 sniffed bytes should be the window setup ending in RAMWR:
```
CMD 0x2A
DAT 0x00 DAT 0x00 DAT 0x00 DAT 0xEF
CMD 0x2B
DAT 0x00 DAT 0x00 DAT 0x00 DAT 0xEF
CMD 0x2C
```

```bash
wsl bash -lc "grep -E 'CMD|DAT' tb/build/sim_init.out | tail -11"
```

Expected: `CMD 0x2A`, four `DAT 0x00/EF`, `CMD 0x2B`, four `DAT 0x00/EF`, `CMD 0x2C`.

If any byte is wrong, `dc` is wrong, or the count is off, that's the bug. Note specifically what diverges.

---

### Task 4: Write `tb/tb_oled_stream.v`

**Files:**
- Create: `tb/tb_oled_stream.v`

- [ ] **Step 1: Write the complete testbench**

```verilog
// tb_oled_stream.v — drives oled_stream with a synthetic pixel_data
// generator (pixel_data = pixel_index, registered). Sniffs mosi while
// sclk_active is high, packs into 16-bit words, prints them. Expected
// sequence: 0x0000, 0x0001, 0x0002, ... If we see anything else (off-by-N,
// bit-reversed, byte-swapped, stuck values), that's the bug.

`timescale 1ns / 1ps

module tb_oled_stream;
    reg clk = 1'b0;
    always #5 clk = ~clk;            // 100 MHz simulated

    reg resetn = 1'b0;
    reg enable = 1'b0;
    initial begin
        #100 resetn = 1'b1;
        #100 enable = 1'b1;
    end

    wire [15:0] pixel_index;
    reg  [15:0] pixel_data;

    // Mimic the BRAM read latency in top.v: pixel_data trails
    // pixel_index by one cycle. With this generator, pixel N has value N.
    always @(posedge clk) pixel_data <= pixel_index;

    wire sclk_active, mosi, cs, dc, frame_done;

    oled_stream dut (
        .clk         (clk),
        .resetn      (resetn),
        .enable      (enable),
        .pixel_index (pixel_index),
        .pixel_data  (pixel_data),
        .sclk_active (sclk_active),
        .mosi        (mosi),
        .cs          (cs),
        .dc          (dc),
        .frame_done  (frame_done)
    );

    // Pixel sniffer: while sclk_active && !cs, sample mosi every clock,
    // pack 16 bits MSB-first, print each completed word with the streamer's
    // current pixel_index for cross-reference.
    reg [15:0] word_buf = 16'd0;
    reg [4:0]  word_bit_cnt = 5'd0;
    integer    pixel_print_count = 0;

    always @(posedge clk) begin
        if (sclk_active && !cs) begin
            if (word_bit_cnt == 5'd15) begin
                $display("[%6t] PIX %0d: 0x%04h (streamer.pixel_index=%0d)",
                         $time, pixel_print_count,
                         {word_buf[14:0], mosi}, pixel_index);
                pixel_print_count <= pixel_print_count + 1;
                word_bit_cnt <= 5'd0;
            end else begin
                word_buf <= {word_buf[14:0], mosi};
                word_bit_cnt <= word_bit_cnt + 5'd1;
            end
        end
    end

    initial begin
        $dumpfile("build/stream.vcd");
        $dumpvars(0, tb_oled_stream);

        wait (enable);
        // Run long enough to capture ~10 pixels (10 * 16 cycles = 160 cycles
        // = 1600 ns at 10 ns/cycle, plus startup/shift overhead).
        #5000;
        $display("[%6t] === STOPPING (sniffed %0d pixels) ===",
                 $time, pixel_print_count);
        $finish;
    end

    // Watchdog
    initial begin
        #1_000_000;
        $display("[%6t] === WATCHDOG TIMEOUT ===", $time);
        $finish;
    end
endmodule
```

---

### Task 5: Run `sim_stream` and capture output

**Files:**
- Reads: `tb/tb_oled_stream.v`, `src/oled_stream.v`
- Writes: `tb/build/sim_stream.vvp`, `tb/build/stream.vcd`

- [ ] **Step 1: Run the simulation**

```bash
wsl bash -lc "cd '/mnt/c/Users/zunmun/Documents/Stuff/Github/PERSONAL PROJECTS/GreyMechaArmy_Tests/io/fpga_oled_fast' && make sim_stream 2>&1 | tee tb/build/sim_stream.out"
```

Expected: 5–10 lines of `PIX n: 0xNNNN (streamer.pixel_index=M)`, then `=== STOPPING ===`.

- [ ] **Step 2: Verify pixel sequence**

```bash
wsl bash -lc "grep 'PIX ' tb/build/sim_stream.out | head -10"
```

Expected: `PIX 0: 0x0000`, `PIX 1: 0x0001`, `PIX 2: 0x0002`, ..., `PIX 9: 0x0009` (or similar; exact count depends on how many fit in 5000 ns).

- [ ] **Step 3: Diagnose any divergence**

If pixel 0 is `0x0000` and pixel 1 is `0x0001` etc., bit ordering and pre-fetch are correct.

If pixel 0 is `0x0001`, that's an off-by-one early — the first pixel was loaded one position ahead.

If pixel 0 is `0x8000` instead of `0x0001`, bit order is reversed (LSB streamed first).

If pixel 0 is `0x0100` instead of `0x0001`, byte order is swapped (LSByte first).

If pixel 0 is `0x0000` and pixel 1 is `0x0000` (same as pixel 0), pixel pre-fetch is broken — pixel_index isn't advancing in time.

If only one pixel printed and then nothing, the reload boundary at `bit_cnt == 0` is broken.

---

### Task 6: Analyze and report findings

**Files:**
- Reads: `tb/build/sim_init.out`, `tb/build/sim_stream.out`
- Writes: short narrative summary (in chat, not a file)

- [ ] **Step 1: Cross-check init bytes against ROM source**

```bash
wsl bash -lc "cd '/mnt/c/Users/zunmun/Documents/Stuff/Github/PERSONAL PROJECTS/GreyMechaArmy_Tests/io/fpga_oled_fast' && grep -E 'CMD|DAT' tb/build/sim_init.out > tb/build/sim_init.bytes"
```

Then verify the byte sequence matches the order in `scripts/gen_gc9a01_init_rom.py` `wr_cmd` / `wr_data` calls (lines 22–203). Spot-check a few critical ones:
- Index 56: CMD 0x3A, then DAT 0x05 (16-bit color format)
- Index ~180: CMD 0x11 (SLPOUT)
- Index ~181: CMD 0x29 (DISPON)
- Then the 11-byte window: 0x2A, 4×data, 0x2B, 4×data, 0x2C

- [ ] **Step 2: Cross-check pixel sequence**

Confirm pixel words are 0, 1, 2, … in order. Note any divergence.

- [ ] **Step 3: Report**

Summarize in chat:
- Init test: PASS / FAIL with first divergent byte
- Stream test: PASS / FAIL with first divergent pixel
- Suspected bug location based on the failure pattern (cross-reference the failure-mode tables in §6 and §7 of the design doc)
- Next debug step (e.g., "fix bit-order in oled_stream.v line N", "ODDR may be the issue and we need a tb_top.v with behavioral primitives", etc.)

If both tests PASS but OLED is still dark on hardware, escalate to the ODDR/integration layer — the design doc §9 lists this as the known gap.

---

## Self-review

**Spec coverage:**
- §5 architecture (`tb/`, `tb/build/`, two TBs) → Tasks 1, 2, 4 ✓
- §6 tb_oled_init driver + sniffer + flow → Task 2 ✓
- §6 expected output verification → Task 3 ✓
- §7 tb_oled_stream driver + sniffer → Task 4 ✓
- §7 expected output + failure interpretations → Task 5 ✓
- §8 Makefile targets → Task 1 ✓
- §10 out-of-scope items → not implemented (correct)

**Placeholder scan:** none.

**Type consistency:** state encoding `S_INIT_PAUSE = 4'd6` matches `src/oled_init.v` after the S_INIT_FETCH state was inserted. Module port names (`init_done`, `ramwr_pulse`, `rearm`, `sclk`, `mosi`, `dc`, `cs`, `rst_n`, `enable`, `pixel_index`, `pixel_data`, `sclk_active`, `frame_done`) all match the production `oled_init.v` and `oled_stream.v` interfaces.

**Known fragility:** the `force dut.pause_cnt = 24'd1` override touches a register inside the DUT. If `pause_cnt` is ever renamed in `oled_init.v`, the testbench breaks silently (pauses re-engage, sim takes 90+ seconds). The testbench should print a warning if pauses dominate sim time — but adding that polish is out of scope for the immediate debug.
