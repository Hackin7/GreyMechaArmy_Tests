# GC9A01 Fast Streaming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the per-byte SPI handshake driver in `io/fpga_oled_fast/` with a sys-clock-rate streaming shifter that paints a full 240×240 GC9A01 frame in ~12 ms (down from ~190 ms).

**Architecture:** Two-module split. `oled_init.v` runs the panel init ROM + window setup + per-frame `0x2C` re-issue at slow SPI (one-shot, doesn't matter how fast). `oled_stream.v` is a 16-bit shift register clocked at sys_clk; SCLK pin driven by `ODDRX1F` so SCLK = sys_clk = 75 MHz. `top.v` owns the PLL, BRAM, button mux, sequencer FSM, and pin-arbitration mux/ODDR.

**Tech Stack:** Verilog (no SystemVerilog), Yosys + nextpnr-ecp5 + ecppack toolchain (WSL), ECP5-25K CABGA256, Lattice ECP5 primitives (`OSCG`, `EHXPLLL`, `ODDRX1F`).

**Reference spec:** `docs/2026-05-06-oled-fast-streaming-design.md` (in this same directory).

**Working directory for all paths below:** `C:/Users/zunmun/Documents/Stuff/Github/PERSONAL PROJECTS/GreyMechaArmy_Tests/io/fpga_oled_fast/`

---

## Notes on testing strategy

This is an FPGA project with no Verilog testbench framework set up. "Tests" in this plan are:
1. **Yosys parse/elaborate** — proves syntax is valid.
2. **Yosys synthesis** — proves the design maps to ECP5 primitives.
3. **nextpnr-ecp5 timing report** — proves the design meets the 75 MHz target.
4. **Hardware bring-up** (Tasks 14–17) — functional validation on the actual board.

All `make` commands assume execution from inside the `fpga_oled_fast/` directory under WSL (or any environment with the toolchain installed). If commands need to be run from PowerShell, prefix with `wsl ` and translate paths.

---

### Task 1: Clean baseline build artifacts in `fpga_oled_fast/`

The directory was copied from `fpga_oled/` and contains stale build outputs. Clear them so subsequent builds start fresh.

**Files:**
- Delete: `fpga_oled.bit`, `fpga_oled.json`, `fpga_oled.svf`, `fpga_oled_out.config`, `tmp.v`
- Delete: `log/` directory contents

- [ ] **Step 1: Remove stale build outputs**

```bash
make clean
```

- [ ] **Step 2: Verify clean state**

```bash
ls
```

Expected: `Makefile pinout.lpf scripts src stonks.mem docs` only (no `.bit`/`.json`/`.svf`/`.config`/`tmp.v`/`log`).

---

### Task 2: Update `Makefile` RTL_ORDER

Drop the soon-to-be-deleted `simple_spi_master.v` and `gc9a01_display.v`. Add the new `oled_init.v` and `oled_stream.v`. Order matters only insofar as the concatenated `tmp.v` is parsed top-to-bottom by Yosys; module-by-module ordering is fine since there are no `include` cross-references between these files.

**Files:**
- Modify: `Makefile` (line 7)

- [ ] **Step 1: Edit the RTL_ORDER variable**

Replace line 7 of `Makefile`:

Before:
```makefile
RTL_ORDER = src/simple_spi_master.v src/btn_debounce.v src/ecp5_oled_pll.v src/gc9a01_display.v src/top.v 
```

After:
```makefile
RTL_ORDER = src/btn_debounce.v src/ecp5_oled_pll.v src/oled_init.v src/oled_stream.v src/top.v 
```

- [ ] **Step 2: Confirm `make tmp.v` fails because new files do not exist yet**

```bash
make tmp.v
```

Expected: error like `cat: src/oled_init.v: No such file or directory`. This is fine — confirms Makefile picked up the new file list.

---

### Task 3: Write `src/oled_init.v` — full module

This module is self-contained: it has its own internal byte shifter (no shared `simple_spi_master`). Once `init_done` goes high it sits idle waiting for `rearm` pulses to issue `0x2C`.

**Files:**
- Create: `src/oled_init.v`

- [ ] **Step 1: Create the file with the complete module**

```verilog
// oled_init.v — GC9A01 init + window setup + per-frame RAMWR re-issue.
// Self-contained byte-level SPI shifter. Slow path; runs at SPI_CLK_DIV-divided SCLK.
module oled_init #(
    parameter integer CLK_HZ = 75000000,
    parameter [7:0] SPI_CLK_DIV = 8'd4
) (
    input  wire clk,
    input  wire resetn,
    output reg  init_done,
    output reg  ramwr_pulse,
    input  wire rearm,
    output reg  sclk,
    output reg  mosi,
    output reg  dc,
    output reg  cs,
    output reg  rst_n
);
`include "gc9a01_init_rom.vh"

    localparam integer RST_LO_CYCLES = CLK_HZ / 500;       // ~2 ms
    localparam integer WAIT10_CYCLES = (CLK_HZ / 1000) * 10;

    // Window-setup byte stream: CASET (0x2A,00,00,00,EF), RASET (0x2B,00,00,00,EF), RAMWR (0x2C)
    function automatic [7:0] win_byte(input integer k);
        case (k)
            0:  win_byte = 8'h2A;
            1:  win_byte = 8'h00;
            2:  win_byte = 8'h00;
            3:  win_byte = 8'h00;
            4:  win_byte = 8'hEF;
            5:  win_byte = 8'h2B;
            6:  win_byte = 8'h00;
            7:  win_byte = 8'h00;
            8:  win_byte = 8'h00;
            9:  win_byte = 8'hEF;
            10: win_byte = 8'h2C;
            default: win_byte = 8'h00;
        endcase
    endfunction
    function automatic win_is_data(input integer k);
        case (k)
            0, 5, 10: win_is_data = 1'b0;
            default:  win_is_data = 1'b1;
        endcase
    endfunction

    // ------- internal byte shifter -------
    reg        sh_active;
    reg        sh_start;
    reg [7:0]  sh_data;
    reg [7:0]  sh_div;
    reg [2:0]  sh_bit;
    reg        sh_phase;     // 0 = SCLK low half, 1 = SCLK high half
    reg        sh_done;

    always @(posedge clk) begin
        sh_done <= 1'b0;
        if (!resetn) begin
            sh_active <= 1'b0;
            sclk      <= 1'b0;
            mosi      <= 1'b0;
            sh_div    <= 0;
            sh_bit    <= 0;
            sh_phase  <= 0;
        end else if (!sh_active) begin
            sclk <= 1'b0;
            if (sh_start) begin
                sh_active <= 1'b1;
                sh_bit    <= 3'd7;
                sh_phase  <= 0;
                sh_div    <= SPI_CLK_DIV;
                mosi      <= sh_data[7];
            end
        end else begin
            if (sh_div != 0)
                sh_div <= sh_div - 8'd1;
            else begin
                sh_div <= SPI_CLK_DIV;
                if (!sh_phase) begin
                    sclk     <= 1'b1;
                    sh_phase <= 1'b1;
                end else begin
                    sclk <= 1'b0;
                    if (sh_bit == 0) begin
                        sh_active <= 1'b0;
                        sh_done   <= 1'b1;
                    end else begin
                        sh_bit   <= sh_bit - 3'd1;
                        mosi     <= sh_data[sh_bit - 3'd1];
                        sh_phase <= 1'b0;
                    end
                end
            end
        end
    end

    // ------- main FSM -------
    localparam [3:0] S_RST_LO     = 4'd0;
    localparam [3:0] S_RST_HI     = 4'd1;
    localparam [3:0] S_WAIT10     = 4'd2;
    localparam [3:0] S_INIT_ISSUE = 4'd3;
    localparam [3:0] S_INIT_WAIT  = 4'd4;
    localparam [3:0] S_INIT_PAUSE = 4'd5;
    localparam [3:0] S_WIN_ISSUE  = 4'd6;
    localparam [3:0] S_WIN_WAIT   = 4'd7;
    localparam [3:0] S_DONE       = 4'd8;
    localparam [3:0] S_REARM_ISS  = 4'd9;
    localparam [3:0] S_REARM_WAIT = 4'd10;

    reg [3:0]  st;
    reg [31:0] timer;
    reg [15:0] init_idx;
    reg [23:0] pause_cnt;
    reg [4:0]  win_idx;

    always @(posedge clk) begin
        sh_start    <= 1'b0;
        ramwr_pulse <= 1'b0;

        if (!resetn) begin
            st        <= S_RST_LO;
            timer     <= 0;
            init_idx  <= 0;
            pause_cnt <= 0;
            win_idx   <= 0;
            init_done <= 1'b0;
            rst_n     <= 1'b0;
            cs        <= 1'b1;
            dc        <= 1'b0;
        end else begin
            case (st)
                S_RST_LO: begin
                    rst_n <= 1'b0;
                    if (timer < RST_LO_CYCLES)
                        timer <= timer + 1;
                    else begin
                        timer <= 0;
                        st    <= S_RST_HI;
                    end
                end
                S_RST_HI: begin
                    rst_n <= 1'b1;
                    st    <= S_WAIT10;
                end
                S_WAIT10: begin
                    if (timer < WAIT10_CYCLES)
                        timer <= timer + 1;
                    else begin
                        timer    <= 0;
                        init_idx <= 0;
                        st       <= S_INIT_ISSUE;
                    end
                end
                S_INIT_ISSUE: begin
                    if (!sh_active) begin
                        sh_data  <= gc9a01_init_byte(init_idx);
                        dc       <= gc9a01_init_is_data(init_idx);
                        cs       <= 1'b0;
                        sh_start <= 1'b1;
                        st       <= S_INIT_WAIT;
                    end
                end
                S_INIT_WAIT: begin
                    if (sh_done) begin
                        cs <= 1'b1;
                        if (gc9a01_init_pause(init_idx) != 0) begin
                            pause_cnt <= gc9a01_init_pause(init_idx);
                            st        <= S_INIT_PAUSE;
                        end else begin
                            if (init_idx + 1 == GC9A01_INIT_LEN) begin
                                win_idx <= 0;
                                st      <= S_WIN_ISSUE;
                            end else begin
                                init_idx <= init_idx + 1;
                                st       <= S_INIT_ISSUE;
                            end
                        end
                    end
                end
                S_INIT_PAUSE: begin
                    if (pause_cnt != 0)
                        pause_cnt <= pause_cnt - 1;
                    else begin
                        if (init_idx + 1 == GC9A01_INIT_LEN) begin
                            win_idx <= 0;
                            st      <= S_WIN_ISSUE;
                        end else begin
                            init_idx <= init_idx + 1;
                            st       <= S_INIT_ISSUE;
                        end
                    end
                end
                S_WIN_ISSUE: begin
                    if (!sh_active) begin
                        sh_data  <= win_byte(win_idx);
                        dc       <= win_is_data(win_idx);
                        cs       <= 1'b0;
                        sh_start <= 1'b1;
                        st       <= S_WIN_WAIT;
                    end
                end
                S_WIN_WAIT: begin
                    if (sh_done) begin
                        cs <= 1'b1;
                        if (win_idx == 5'd10) begin
                            init_done <= 1'b1;
                            st        <= S_DONE;
                        end else begin
                            win_idx <= win_idx + 1;
                            st      <= S_WIN_ISSUE;
                        end
                    end
                end
                S_DONE: begin
                    cs    <= 1'b1;
                    sclk  <= 1'b0;
                    mosi  <= 1'b0;
                    if (rearm)
                        st <= S_REARM_ISS;
                end
                S_REARM_ISS: begin
                    if (!sh_active) begin
                        sh_data  <= 8'h2C;       // RAMWR
                        dc       <= 1'b0;        // command
                        cs       <= 1'b0;
                        sh_start <= 1'b1;
                        st       <= S_REARM_WAIT;
                    end
                end
                S_REARM_WAIT: begin
                    if (sh_done) begin
                        cs          <= 1'b1;
                        ramwr_pulse <= 1'b1;
                        st          <= S_DONE;
                    end
                end
                default: st <= S_RST_LO;
            endcase
        end
    end
endmodule
```

- [ ] **Step 2: Verify it parses** (need a stub `oled_stream.v` — created in Task 4)

(Skip standalone parse for now; full project elaboration happens in Task 6.)

---

### Task 4: Write `src/oled_stream.v` — full module

The hot loop. One MOSI bit per sys_clk; pixel pre-fetch handled by incrementing `pixel_index` 3 cycles before the shift register reload (BRAM read = 1 cycle latency, button mux register = 1 cycle, plus 1 cycle margin).

**Files:**
- Create: `src/oled_stream.v`

- [ ] **Step 1: Create the file with the complete module**

```verilog
// oled_stream.v — continuous 16-bit-per-pixel shifter for GC9A01 pixel data.
// Designed to run with sys_clk == SCLK rate; SCLK pin is driven externally
// by an ODDRX1F in top.v. This module just provides `sclk_active` (gate
// signal for ODDR) and the current `mosi` bit, plus cs/dc.
module oled_stream (
    input  wire        clk,
    input  wire        resetn,
    input  wire        enable,
    output reg  [15:0] pixel_index,
    input  wire [15:0] pixel_data,
    output reg         sclk_active,
    output reg         mosi,
    output reg         cs,
    output reg         dc,
    output reg         frame_done
);
    localparam integer LAST_PIX = 16'd57599;   // 240*240 - 1

    reg [15:0] shift;
    reg [3:0]  bit_cnt;
    reg        streaming;

    always @(posedge clk) begin
        frame_done <= 1'b0;

        if (!resetn || !enable) begin
            pixel_index <= 16'd0;
            shift       <= 16'd0;
            bit_cnt     <= 4'd15;
            streaming   <= 1'b0;
            sclk_active <= 1'b0;
            mosi        <= 1'b0;
            cs          <= 1'b1;
            dc          <= 1'b1;
        end else if (!streaming) begin
            // First cycle after enable. pixel_data is already valid because
            // pixel_index has been 0 in idle and BRAM/mux fed pixel 0 through.
            shift       <= pixel_data;
            bit_cnt     <= 4'd15;
            mosi        <= pixel_data[15];
            cs          <= 1'b0;
            dc          <= 1'b1;
            sclk_active <= 1'b1;
            streaming   <= 1'b1;
            pixel_index <= 16'd0;
        end else begin
            // Default: shift one bit out
            shift   <= {shift[14:0], 1'b0};
            mosi    <= shift[14];
            bit_cnt <= bit_cnt - 4'd1;

            // Pre-fetch: 3 cycles before reload, advance pixel_index so BRAM
            // (1 cyc) + button-mux register (1 cyc) + margin (1 cyc) settles by
            // the bit_cnt==0 reload.
            if (bit_cnt == 4'd3 && pixel_index < LAST_PIX)
                pixel_index <= pixel_index + 16'd1;

            // Reload boundary: bit_cnt was 0 last cycle; load next pixel
            if (bit_cnt == 4'd0) begin
                bit_cnt <= 4'd15;
                shift   <= pixel_data;
                mosi    <= pixel_data[15];
                if (pixel_index == LAST_PIX) begin
                    streaming   <= 1'b0;
                    sclk_active <= 1'b0;
                    cs          <= 1'b1;
                    frame_done  <= 1'b1;
                end
            end
        end
    end
endmodule
```

---

### Task 5: Rewrite `src/top.v`

Owns clock (OSCG → PLL → 75 MHz), reset, BRAM, button debounce + color overlay mux, sequencer FSM, pin-arbitration mux, and ODDRX1F instances for the SCLK and MOSI output pins.

**Files:**
- Modify (full rewrite): `src/top.v`

- [ ] **Step 1: Replace `src/top.v` entirely**

```verilog
// top.v — fast streaming GC9A01 driver.
// btn[0]=image (stonks.mem, OOB read preserved per design), btn[1]=R, btn[2]=G,
// btn[3]=B, btn[4]=pink. D12=grey. C12=async reset (active low).
module top (
    input  wire       clk_ext,
    input  wire [4:0] btn,
    input  wire       btn_grey_n,
    input  wire       btn_rst_n,
    output wire [7:0] led,
    inout  wire [7:0] interconnect,
    inout  wire [7:0] pmod_j1,
    inout  wire [7:0] pmod_j2,
    output wire       oled_scl,
    output wire       oled_sda,
    output wire       oled_dc,
    output wire       oled_cs,
    output wire       oled_rst,
    inout  wire [4:0] s
);
    localparam integer CLK_HZ = 75000000;

    localparam integer IMG_W = 96;
    localparam integer IMG_H = 64;

    // ---- Clock: OSCG → PLL → 75 MHz ----
    wire osc_clk;
    defparam OSCI1.DIV = "6";
    OSCG OSCI1 (.OSC(osc_clk));

    wire sys_clk, pll_locked;
    ecp5_oled_pll u_pll (
        .clki   (osc_clk),
        .clko   (sys_clk),
        .locked (pll_locked)
    );

    wire unused_clk_ext = clk_ext;

    // ---- Reset (button + sync, gated by PLL lock) ----
    wire reset_button = ~btn_rst_n;
    reg  [1:0] reset_sync = 2'b11;
    reg  [7:0] reset_counter = 0;
    wire reset_request = reset_sync[1];
    wire resetn = (&reset_counter) & pll_locked;

    always @(posedge sys_clk) begin
        reset_sync <= {reset_sync[0], reset_button};
        if (reset_request)
            reset_counter <= 0;
        else if (!(&reset_counter))
            reset_counter <= reset_counter + 1;
    end

    // ---- Buttons ----
    wire [4:0] btn_press;
    wire       grey_press;
    btn_debounce #(.WIDTH(5), .STABLE_CYCLES(4096)) u_deb (
        .clk(sys_clk), .resetn(resetn), .btn_n(btn), .btn_press(btn_press)
    );
    btn_debounce #(.WIDTH(1), .STABLE_CYCLES(4096)) u_grey (
        .clk(sys_clk), .resetn(resetn), .btn_n(btn_grey_n), .btn_press(grey_press)
    );

    // ---- Image BRAM (synchronous read) ----
    // Size matches the source .mem file (96*64 = 6144 entries). The OOB read
    // when pixel_index > 6143 is intentional (preserved current behavior).
    reg [15:0] image_memory [0:IMG_W*IMG_H - 1];
    initial $readmemh("stonks.mem", image_memory);

    wire [15:0] stream_pixel_index;
    reg  [15:0] image_pixel_data_r;
    always @(posedge sys_clk)
        image_pixel_data_r <= image_memory[stream_pixel_index];

    // ---- Button-overlay mux (registered) ----
    reg [15:0] pixel_to_stream;
    always @(posedge sys_clk) begin
        if      (grey_press)   pixel_to_stream <= 16'hFFE0;
        else if (btn_press[4]) pixel_to_stream <= 16'hFE19;
        else if (btn_press[3]) pixel_to_stream <= 16'h001F;
        else if (btn_press[2]) pixel_to_stream <= 16'h07E0;
        else if (btn_press[1]) pixel_to_stream <= 16'hF800;
        else if (btn_press[0]) pixel_to_stream <= image_pixel_data_r;
        else                   pixel_to_stream <= 16'hFFFF;
    end

    // ---- Init module ----
    wire init_done;
    wire ramwr_pulse;
    reg  rearm;
    wire init_sclk, init_mosi, init_dc, init_cs, init_rst_n;
    oled_init #(
        .CLK_HZ      (CLK_HZ),
        .SPI_CLK_DIV (8'd4)
    ) u_init (
        .clk         (sys_clk),
        .resetn      (resetn),
        .init_done   (init_done),
        .ramwr_pulse (ramwr_pulse),
        .rearm       (rearm),
        .sclk        (init_sclk),
        .mosi        (init_mosi),
        .dc          (init_dc),
        .cs          (init_cs),
        .rst_n       (init_rst_n)
    );

    // ---- Stream module ----
    reg  stream_enable;
    wire stream_sclk_active, stream_mosi, stream_cs, stream_dc, stream_frame_done;
    oled_stream u_stream (
        .clk         (sys_clk),
        .resetn      (resetn),
        .enable      (stream_enable),
        .pixel_index (stream_pixel_index),
        .pixel_data  (pixel_to_stream),
        .sclk_active (stream_sclk_active),
        .mosi        (stream_mosi),
        .cs          (stream_cs),
        .dc          (stream_dc),
        .frame_done  (stream_frame_done)
    );

    // ---- Sequencer FSM ----
    localparam [1:0] SEQ_WAIT_INIT = 2'd0;
    localparam [1:0] SEQ_STREAM    = 2'd1;
    localparam [1:0] SEQ_REARM     = 2'd2;
    reg [1:0] seq;

    always @(posedge sys_clk) begin
        rearm <= 1'b0;
        if (!resetn) begin
            seq           <= SEQ_WAIT_INIT;
            stream_enable <= 1'b0;
        end else begin
            case (seq)
                SEQ_WAIT_INIT: begin
                    stream_enable <= 1'b0;
                    if (init_done)
                        seq <= SEQ_STREAM;
                end
                SEQ_STREAM: begin
                    stream_enable <= 1'b1;
                    if (stream_frame_done) begin
                        stream_enable <= 1'b0;
                        seq           <= SEQ_REARM;
                    end
                end
                SEQ_REARM: begin
                    stream_enable <= 1'b0;
                    rearm         <= 1'b1;
                    if (ramwr_pulse)
                        seq <= SEQ_STREAM;
                end
                default: seq <= SEQ_WAIT_INIT;
            endcase
        end
    end

    // ---- Pin arbitration + ODDR ----
    wire stream_owns = stream_enable;

    // SCLK: ODDRX1F at sys_clk; D0=1, D1=0 produces sys_clk waveform on pin
    wire sclk_d0 = stream_owns ? stream_sclk_active : init_sclk;
    wire sclk_d1 = stream_owns ? 1'b0               : init_sclk;
    ODDRX1F u_sclk (
        .SCLK (sys_clk),
        .RST  (~resetn),
        .D0   (sclk_d0),
        .D1   (sclk_d1),
        .Q    (oled_scl)
    );

    // MOSI: ODDR with D0==D1==current bit so it's stable across full SCLK period
    wire mosi_bit = stream_owns ? stream_mosi : init_mosi;
    ODDRX1F u_mosi (
        .SCLK (sys_clk),
        .RST  (~resetn),
        .D0   (mosi_bit),
        .D1   (mosi_bit),
        .Q    (oled_sda)
    );

    assign oled_cs  = stream_owns ? stream_cs : init_cs;
    assign oled_dc  = stream_owns ? stream_dc : init_dc;
    assign oled_rst = init_rst_n;

    // ---- Status / unused outputs ----
    assign led = {1'b0, pll_locked, grey_press, btn_press};

    assign interconnect = 8'bz;
    assign pmod_j1      = 8'bz;
    assign pmod_j2      = 8'bz;
    assign s            = 5'bz;
endmodule
```

---

### Task 6: Delete the old SPI master and display modules

**Files:**
- Delete: `src/simple_spi_master.v`
- Delete: `src/gc9a01_display.v`

- [ ] **Step 1: Delete the obsolete files**

```bash
rm src/simple_spi_master.v src/gc9a01_display.v
```

- [ ] **Step 2: Verify directory contents**

```bash
ls src/
```

Expected: `btn_debounce.v ecp5_oled_pll.v gc9a01_init_rom.vh oled_init.v oled_stream.v top.v`.

---

### Task 7: Run Yosys synthesis (no P&R yet)

**Files:**
- Reads: all RTL listed in `Makefile` `RTL_ORDER` plus `src/gc9a01_init_rom.vh`
- Writes: `tmp.v`, `fpga_oled.json`, `log/yosys.log`

- [ ] **Step 1: Build the json**

```bash
make fpga_oled.json
```

Expected: exits 0. If errors, fix the offending file (likely a typo or undefined identifier in the new modules) and re-run.

- [ ] **Step 2: Confirm `image_memory` is mapped to BRAM, not LUT-RAM**

```bash
grep -i "block ram\|EBR\|image_memory" log/yosys.log
```

Expected: at least one line indicating `image_memory` was mapped to a block RAM (look for "Mapping" / "EBR" / "$mem_v2"). If you see a warning that it stayed as LUT-based memory, the BRAM inference failed — most likely the `initial $readmemh` was rejected, or the read isn't synchronous. Verify `image_pixel_data_r` is updated inside `always @(posedge sys_clk)`.

- [ ] **Step 3: Confirm `OSCG`, `EHXPLLL`, and `ODDRX1F` instances are present**

```bash
grep -E "OSCG|EHXPLLL|ODDRX1F" log/yosys.log
```

Expected: each primitive name appears at least once (instance count or "Mapping" reference).

---

### Task 8: Run nextpnr-ecp5 (place-and-route at 75 MHz)

**Files:**
- Reads: `fpga_oled.json`, `pinout.lpf`
- Writes: `fpga_oled_out.config`, `log/nextpnr-ecp5.log`

- [ ] **Step 1: Run P&R**

```bash
make fpga_oled_out.config
```

Note: the `Makefile` already passes `--freq 75`. nextpnr-ecp5's `--freq` is a fallback used only when no explicit clock constraint exists; it is the right knob here since `sys_clk` is generated internally and isn't constrained in `pinout.lpf`.

- [ ] **Step 2: Check timing pass at 75 MHz**

```bash
grep -i "max frequency\|FAIL\|Worst case slack\|timing failed" log/nextpnr-ecp5.log
```

Expected: a line like `Max frequency for clock 'sys_clk_$glb_clk': XX.XX MHz (PASS at 75.00 MHz)`. If `FAIL`, look at the slack report for the worst path.
- If the failing path is in `oled_init`, that's surprising (slow logic) — most likely a long combinational chain inside the byte shifter. Add a pipeline register on the bit-mux output if needed.
- If it's the BRAM read combined with the pixel mux, register `image_pixel_data_r` separately from `pixel_to_stream` (already split in this design — confirm both are flopped).
- Last resort: drop PLL output to 50 MHz (Task 9 covers this fallback).

- [ ] **Step 3: Confirm `ODDRX1F` instances on the SCLK and SDA pins**

```bash
grep "ODDRX1F" log/nextpnr-ecp5.log
```

Expected: two `ODDRX1F` cells placed (one for `oled_scl`, one for `oled_sda`).

---

### Task 9: Generate the bitstream

- [ ] **Step 1: Build `.bit` and `.svf`**

```bash
make
```

Expected: completes with `fpga_oled.bit` and `fpga_oled.svf` produced. Sizes should be similar to the original `fpga_oled/` build (a few hundred KB).

- [ ] **Step 2: Confirm output files exist**

```bash
ls -la fpga_oled.bit fpga_oled.svf
```

---

### Task 10: Hardware bring-up step 1 — init only (force `enable=0`)

This validates the init path in isolation before letting the streamer touch the panel. The display should show whatever the panel's RAM defaults to after init (likely garbage or a uniform color), proving init completed.

**Files:**
- Modify (temporarily): `src/top.v` sequencer FSM (force `stream_enable` low)

- [ ] **Step 1: Temporarily force `stream_enable` to 0**

In `src/top.v`, locate the sequencer FSM block. Replace:

```verilog
                SEQ_STREAM: begin
                    stream_enable <= 1'b1;
```

with:

```verilog
                SEQ_STREAM: begin
                    stream_enable <= 1'b0;   // TEMP: bring-up step 1
```

- [ ] **Step 2: Rebuild and flash**

```bash
make clean && make
```

Then flash via your normal route (RP2350 fpga loader on the badge, or `openFPGALoader` if using an external programmer).

- [ ] **Step 3: Observe panel**

Expected: panel powers on, backlight (if present) on, display shows uniform color or random pattern. If the panel stays completely dark:
- Check `oled_rst` line — it should pulse low for ~2 ms then go high.
- Check that `pll_locked` LED bit (LED[6]) goes high shortly after power-on (`led = {1'b0, pll_locked, grey_press, btn_press}`).

- [ ] **Step 4: Restore the line**

Revert the temp change:

```verilog
                SEQ_STREAM: begin
                    stream_enable <= 1'b1;
```

---

### Task 11: Hardware bring-up step 2 — streaming at 50 MHz

Validates the streaming logic with a conservative SCLK that any GC9A01 sample should accept.

**Files:**
- Modify (temporarily): `src/ecp5_oled_pll.v` parameter `CLKOP_DIV`

- [ ] **Step 1: Drop PLL output to 50 MHz**

In `src/ecp5_oled_pll.v`, the PLL is configured as `(50 MHz × CLKFB_DIV) / CLKOP_DIV = (50 × 3) / 8 = 18.75 MHz × 4 = 75 MHz` after the inferred VCO doubling — actually the existing constants give 75 MHz; for 50 MHz output, change:

Before (around line 25):
```verilog
        .CLKOP_DIV(8),
```

After:
```verilog
        .CLKOP_DIV(12),
```

(VCO = CLKFB_DIV × CLKOP_DIV × CLKOP_freq = 3 × 8 × 75 = 1800 MHz / 1800 MHz... double-check by reading the `(* FREQUENCY_PIN_CLKOP="75" *)` annotation and updating it to `"50"`.)

Also update:
```verilog
(* FREQUENCY_PIN_CLKOP="50" *)
```

And in `src/top.v` change `localparam integer CLK_HZ = 75000000;` → `50000000`.

- [ ] **Step 2: Rebuild and flash**

```bash
make clean && make
```

Note: also update the `nextpnr-ecp5` `--freq` if you want it stricter. The default `TARGET_FREQ_MHZ ?= 75` in `Makefile` is fine — passing a higher number than actual sys_clk just means the timing report has more headroom.

- [ ] **Step 3: Observe panel**

Expected: clean image (the OOB-read garbage from `image_memory`, but uniform and stable, not banded). Press buttons → solid color frames. Frame load should appear instant or near-instant (~18 ms at 50 MHz SCLK).

If the image looks corrupted (banded, wrong colors, vertical stripes):
- Check the BRAM pre-fetch timing — try changing `if (bit_cnt == 4'd3 ...)` to `4'd4` or `4'd2` in `oled_stream.v`.
- Check ODDR alignment — try `D0=D1=mosi_bit` swapped to `D0=~mosi_bit, D1=mosi_bit` (180° MOSI shift).

---

### Task 12: Hardware bring-up step 3 — streaming at 75 MHz

- [ ] **Step 1: Restore PLL to 75 MHz**

In `src/ecp5_oled_pll.v` revert `CLKOP_DIV` back to `8` and `FREQUENCY_PIN_CLKOP` back to `"75"`. In `src/top.v` revert `CLK_HZ` to `75000000`.

- [ ] **Step 2: Rebuild and flash**

```bash
make clean && make
```

- [ ] **Step 3: Observe panel**

Expected: same clean image as Task 11, frame load ~12 ms (~80 fps — should look fully instantaneous, no perceptible scan).

If banding / column smear / wrong colors appear (and Task 11 was clean), the panel doesn't tolerate 75 MHz SCLK on this wiring. Permanent fallback: revert to 50 MHz config from Task 11 step 1 and ship that.

---

### Task 13: Verify button overlays still work

- [ ] **Step 1: With Task 12's bitstream flashed, exercise each button**

| Button | Expected color |
|---|---|
| (none pressed) | white (`0xFFFF`) |
| btn[0] | image (stretched/OOB read of stonks.mem) |
| btn[1] | red (`0xF800`) |
| btn[2] | green (`0x07E0`) |
| btn[3] | blue (`0x001F`) |
| btn[4] | pink (`0xFE19`) |
| btn_grey (D12) | grey (`0xFFE0`) — overrides others |

Each color must be **perfectly uniform** with no banding. Banding on a solid-color frame indicates a streaming-path bug (data line glitching or pre-fetch desync).

---

## Self-review

**Spec coverage:**
- §3.2 refactor scope (delete old, create new, rewrite top) → Tasks 3, 4, 5, 6 ✓
- §5.1 oled_init interface and FSM → Task 3 ✓
- §5.2 oled_stream interface, shifter, pre-fetch → Task 4 ✓
- §5.3 top.v clock/reset/BRAM/buttons/sequencer/ODDR → Task 5 ✓
- §6 SPI timing alignment via ODDR D0/D1 patterns → Task 5 (ODDR instantiation) ✓
- §7.1 synthesis verification (BRAM inference, ODDR, timing) → Tasks 7, 8 ✓
- §7.2 incremental hardware bring-up (init only → 50 MHz → 75 MHz) → Tasks 10, 11, 12 ✓
- §7.3 button test patterns → Task 13 ✓
- §7.4 failure-mode triage → referenced inline in bring-up tasks ✓

**Placeholder scan:** none.

**Type consistency:** signal names match between `oled_stream.v` (Task 4), `oled_init.v` (Task 3), and `top.v` instantiations (Task 5):
- `init_done`, `ramwr_pulse`, `rearm`, `sclk`, `mosi`, `dc`, `cs`, `rst_n` — consistent.
- `enable`, `pixel_index`, `pixel_data`, `sclk_active`, `mosi`, `cs`, `dc`, `frame_done` — consistent.

**Known fragility:** the PLL `CLKOP_DIV` math in Task 11 assumes I have the original PLL constants right. The implementer should double-check by reading the existing `ecp5_oled_pll.v` and computing the VCO frequency before flashing.
