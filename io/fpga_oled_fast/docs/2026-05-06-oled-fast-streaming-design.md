# GC9A01 OLED Fast Streaming Driver — Design

**Date:** 2026-05-06
**Status:** Approved (brainstorming complete, ready for implementation plan)
**Working dir:** `io/fpga_oled_fast/` (forked from `io/fpga_oled/`, original untouched as reference)

## 1. Problem

The existing GC9A01 driver (`io/fpga_oled/`) refreshes the 240×240 panel slowly enough that the user can see the image painting top-to-bottom. Goal: make the frame appear instantaneously (no perceptible scan).

### 1.1 Current bottlenecks

- **Sys clock:** ECP5 internal `OSCG` at `DIV=6` ≈ 50 MHz. The PLL (`ecp5_oled_pll.v`) is written but not wired up.
- **SPI clock:** `SPI_CLK_DIV=4` → SCLK = 50 MHz / (2·5) = **5 MHz**.
- **Per-pixel cost:** 2 bytes × 8 bits × 2 SCLK halves × 5 sys-cycles + per-byte FSM handshake (`S_FRAME_HEAD → S_PHI_ISS → S_PHI_WAIT → S_PLO_WAIT`, ~6 cycles idle between bytes) ≈ **166 cycles ≈ 3.3 µs/pixel**.
- **Per-frame:** 240×240 × 3.3 µs ≈ **190 ms (~5 fps)** — visibly scans.

### 1.2 Constraints

- No external oscillator (use `OSCG` + on-chip PLL only).
- ECP5-25K, CABGA256 package; toolchain is yosys + nextpnr-ecp5 in WSL.
- Pin assignments in `pinout.lpf` are fixed (board hardware).

## 2. Goal

Frame load time ≤ 16 ms (≥60 fps) — below visual-persistence threshold so no scan is perceivable. Stretch target ≤ 12 ms.

## 3. Approach

**Replace the per-byte SPI handshake with a continuous bit shifter clocked at sys-clock rate via `ODDRX1F`. Use the existing PLL to lift sys clock to 75 MHz.**

- SCLK pin at 75 MHz (sys clock rate, via `ODDRX1F` D0=1, D1=0).
- One MOSI bit per sys clock; pixel pre-fetched from BRAM with no inter-pixel gap.
- Frame time: 16 cycles/pixel × 57600 pixels ÷ 75 MHz = **12.29 ms/frame ≈ 81 fps**.

### 3.1 Approach trade-off summary

| Approach | Frame time | Risk | Chosen |
|---|---|---|---|
| A. Just drop `SPI_CLK_DIV` | ~50 ms | Low | No (still perceptible) |
| B. PLL + tighter byte-streaming FSM | ~25 ms | Medium | Fallback if C fails |
| **C. PLL + ODDR + raw streaming shifter** | **~12 ms** | **Medium** | **Yes** |

### 3.2 Refactor scope

- Delete `simple_spi_master.v` and `gc9a01_display.v` (replaced).
- New: `oled_init.v`, `oled_stream.v`.
- Rewrite: `top.v`.
- Unchanged: `ecp5_oled_pll.v`, `btn_debounce.v`, `gc9a01_init_rom.vh`, `pinout.lpf`, `stonks.mem`, `Makefile`.

## 4. Architecture

```
                    ┌─────────────────┐
   OSCG (~50 MHz) ──┤ ecp5_oled_pll   ├── sys_clk (75 MHz)
                    └─────────────────┘
                              │
                    ┌─────────┴──────────────────────────────────┐
                    │                  top.v                     │
                    │   ┌────────────┐    ┌──────────────────┐   │
                    │   │ image_mem  │    │ reset / debounce │   │
                    │   │ (BRAM)     │    │ + button mux     │   │
                    │   └─────┬──────┘    └──────────────────┘   │
                    │         │                                  │
                    │   ┌─────▼──────┐         ┌──────────────┐  │
                    │   │ oled_init  ├────────►│ pin arbiter  │  │
                    │   │ (slow SPI) │  init   │ + ODDRX1F on │──┼──► oled_scl/sda/dc/cs/rst
                    │   └────────────┘ done?   │ SCLK and MOSI│  │
                    │   ┌─────▼──────┐ pixel   └──────▲───────┘  │
                    │   │oled_stream ├──stream────────┘          │
                    │   │ (fast SPI) │                           │
                    │   └────────────┘                           │
                    └────────────────────────────────────────────┘
```

## 5. Module specifications

### 5.1 `oled_init.v` (slow path)

**Purpose:** bring panel up after reset; re-issue `0x2C` between frames.

**Interface:**
```
input  clk, resetn
output init_done       // high once panel ready for pixel stream
output ramwr_pulse     // 1-cycle pulse after each 0x2C re-issue
input  rearm           // top.v asserts to request another 0x2C
output sclk, mosi, dc, cs
output rst_n           // panel hardware reset line
```

**Internals:**
- Internal byte shifter, `SPI_CLK_DIV=4` (→ ~7.5 MHz SCLK at sys=75 MHz, plenty of margin).
- States: `RST_LO → RST_HI → WAIT10ms → INIT_ISSUE/WAIT/PAUSE (loop ROM) → WIN_ISSUE/WAIT (CASET+RASET+RAMWR, 11 bytes) → DONE`.
- After `DONE`, on `rearm` high: send one byte `0x2C`, pulse `ramwr_pulse`, return to `DONE`.
- Per-byte CS deassert (`keep_cs = 0`) is preserved — init commands are short, separate transactions.

### 5.2 `oled_stream.v` (fast path)

**Purpose:** stream one full frame (57600 pixel words) back-to-back at sys-clock rate.

**Interface:**
```
input  clk, resetn
input  enable                   // top asserts after init_done + ramwr_pulse
output reg [15:0] pixel_index   // → top → BRAM address
input      [15:0] pixel_data    // ← top, registered BRAM read result
output sclk_active              // 1 = SCLK pin should toggle at sys_clk; 0 = hold low
output mosi                     // current bit (driven via top's ODDR)
output cs                       // low during stream
output dc                       // high (pixel data)
output frame_done               // 1-cycle pulse after last bit of last pixel
```

**Internals:**
- `shift [15:0]` — current pixel, MSB first.
- `bit_cnt [3:0]` — counts 15 → 0 each pixel.
- `pixel_index [15:0]` — 0 → 57599.
- BRAM read pre-fetch: increment `pixel_index` two cycles before bit_cnt rolls (registered button-mux adds one cycle).
- `mosi <= shift[15]`; on each sys_clk: `shift <= {shift[14:0], 1'b0}`, `bit_cnt <= bit_cnt - 1` (wrap at 0 → load new pixel).
- `sclk_active <= enable && streaming` — gates ODDR so SCLK is silent before and after the frame.

**Timing:** 16 sys_clks/pixel × 57600 pixels = 921,600 cycles ÷ 75 MHz = **12.29 ms/frame**.

### 5.3 `top.v` (orchestration)

**Clock & reset:**
```verilog
wire osc_clk;
defparam OSCI1.DIV = "6";       // ~50 MHz
OSCG OSCI1 (.OSC(osc_clk));

wire sys_clk, pll_locked;
ecp5_oled_pll u_pll (.clki(osc_clk), .clko(sys_clk), .locked(pll_locked));

// resetn: button + sync counter, gated additionally by pll_locked
```

**BRAM read** (registered, 1-cycle latency):
```verilog
reg [15:0] image_pixel_data_r;
always @(posedge sys_clk)
    image_pixel_data_r <= image_memory[pixel_index_from_stream];
```
Note: image stretcher bug (OOB read into 6144-element array with 16-bit index) is intentionally **preserved** per design discussion — out of scope for this work.

**Button-overlay mux** (registered, adds 1 cycle latency that pre-fetch accounts for):
```verilog
reg [15:0] pixel_to_stream;
always @(posedge sys_clk) begin
    if      (grey_press)     pixel_to_stream <= 16'hFFE0;
    else if (btn_press[4])   pixel_to_stream <= 16'hFE19;
    else if (btn_press[3])   pixel_to_stream <= 16'h001F;
    else if (btn_press[2])   pixel_to_stream <= 16'h07E0;
    else if (btn_press[1])   pixel_to_stream <= 16'hF800;
    else if (btn_press[0])   pixel_to_stream <= image_pixel_data_r;
    else                     pixel_to_stream <= 16'hFFFF;
end
```

**Sequencer FSM:**
```
WAIT_INIT  → wait for oled_init.init_done           → STREAM
STREAM     → assert oled_stream.enable;
             on frame_done                          → REARM_2C
REARM_2C   → deassert enable; pulse oled_init.rearm;
             wait for oled_init.ramwr_pulse         → STREAM
```

**Pin arbitration & ODDR:**
```verilog
wire stream_owns = stream_enable_r;

// SCLK pin via ODDR — toggles at sys_clk during stream, mirrors init_sclk otherwise
wire sclk_d0 = stream_owns ? stream_sclk_active : init_sclk;
wire sclk_d1 = stream_owns ? 1'b0               : init_sclk;
ODDRX1F u_sclk (.SCLK(sys_clk), .RST(~resetn), .D0(sclk_d0), .D1(sclk_d1), .Q(oled_scl));

// MOSI pin via ODDR — D0=D1=bit so data is stable for full SCLK period
wire mosi_bit = stream_owns ? stream_mosi : init_mosi;
ODDRX1F u_mosi (.SCLK(sys_clk), .RST(~resetn), .D0(mosi_bit), .D1(mosi_bit), .Q(oled_sda));

// CS / DC / RST: plain mux, no ODDR
assign oled_cs  = stream_owns ? stream_cs : init_cs;
assign oled_dc  = stream_owns ? stream_dc : init_dc;
assign oled_rst = init_rst_n;
```

**Why ODDR on MOSI even though it doesn't change at sub-cycle rate:** matches pin-driver delay between SCLK and MOSI. Without it, plain-flop MOSI vs ODDR SCLK have different output paths and skew at 75 MHz.

**Unchanged:** `btn_debounce` instances, `interconnect`/`pmod`/`s` tristates, `led` assignment.

## 6. SPI timing alignment

GC9A01 expects SPI mode 0 (CPOL=0 idle low, CPHA=0 sample on rising SCLK).

- SCLK pin = sys_clk waveform (via ODDR `D0=1, D1=0`).
- MOSI pin = current bit, stable for full sys_clk period (via ODDR `D0=D1=bit`).
- Slave samples at SCLK rising edge = mid-period of the MOSI bit → ample setup/hold margin.

## 7. Verification & bring-up plan

### 7.1 Synthesis (WSL)
1. `make clean && make` from `io/fpga_oled_fast/`. Must complete with no errors.
2. Check `log/yosys.log` — confirm `image_memory` mapped to EBR (BRAM), not LUT-RAM.
3. Check `log/nextpnr-ecp5.log` — confirm timing pass at 75 MHz on `sys_clk`. If fails, look at slack on init logic or BRAM read; add a pipeline stage where slack is negative.
4. Confirm `ODDRX1F` instances on `oled_scl` and `oled_sda` pins in nextpnr report.

### 7.2 Hardware bring-up (incremental)
1. **First flash with `enable=0` permanently** — display whatever init paints. Validates init path in isolation.
2. **Enable streaming, PLL output dialed to 50 MHz** (one-line change in `ecp5_oled_pll.v`'s `CLKOP_DIV`). Confirm clean image at 50 MHz SCLK. Validates stream logic.
3. **Crank PLL back to 75 MHz**, reflash. If clean → done. If banding/wrong colors/column smear → 75 MHz too fast for this panel sample; revert to 50 MHz permanently.

### 7.3 Built-in test patterns
Buttons (preserved feature) force solid-color frames. Solid red/green/blue/grey should be perfectly uniform — any banding indicates a streamer or pin-timing bug.

### 7.4 Failure-mode triage

| Symptom | Likely cause |
|---|---|
| Black screen | Init didn't complete; RST polarity wrong; PLL not locking |
| Half-screen / partial frame | Stream stalled mid-frame (BRAM pipe race or `frame_done`/`rearm` handshake bug) |
| Visible scan still slow | `enable` not asserting; check `stream_owns` |
| Banding / wrong colors | SCLK too fast for panel — drop PLL to 50 MHz |
| Image shifted by N pixels | BRAM pre-fetch off-by-one; adjust `bit_cnt` threshold for `pixel_index` increment |

## 8. Out of scope

- Image stretcher fix (current OOB read preserved).
- Dynamic frame content / framebuffer updates from CPU.
- Tearing-effect (TE) pin support — not connected on this board.
- Double buffering — image is static.
- Power optimization.
