// top.v — dual-clock-domain bridge between the EE2026 Top_Student design
// and the greybadge GC9A01 OLED.
//
//   Slow domain (sys_clk_slow ≈ 12.5 MHz):
//     • Top_Student (EE2026) — fits its 32-bit math comfortably.
//     • scan_idx counter walks 0..6143; for each address Top_Student
//       produces oled_pixel_data which is written into the back buffer.
//   Fast domain (sys_clk_fast = 75 MHz):
//     • oled_gc9a01 — runs the OLED at full streaming rate.
//     • image_stretch — converts 240×240 pixel_index to 96×64 image_idx.
//     • frame_buffer read — fetches the rendered pixel from the front buffer.
//
//   CDC: dual-clock, double-buffered BRAM in `frame_buffer.v`. Swaps align
//   to OLED frame boundary (oled_gc9a01.streaming falling edge), so visible
//   tearing is eliminated even when EE2026 animations move quickly.
//
// Button mapping:
//   btn[0..4]    → btnL/U/C/D/R (forwarded into Top_Student in slow domain)
//   btn_mecha[0] (D12) — press to cycle aspect mode (CIRCLE → FULL → ASPECT → ...)
//   btn_mecha[1] (C12) — held LOW = system reset (both domains).
//                        Each press also advances task selection
//                        (A → B → C → D → A). task_idx is *not* reset by
//                        resetn so the choice survives the reset.
module top (
    input  wire       clk_ext,
    input  wire [4:0] btn,
    input  wire [1:0] btn_mecha,        // [0]=grey/aspect, [1]=rst+task-cycle
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
    localparam integer CLK_FAST_HZ = 75_000_000;

    // ---- Clocks: OSCG /6 → PLL → 75 MHz (fast) + 12.5 MHz (slow) ----
    wire osc_clk;
    defparam OSCI1.DIV = "6";
    OSCG OSCI1 (.OSC(osc_clk));

    wire sys_clk_fast, sys_clk_slow, pll_locked;
    ecp5_dual_pll u_pll (
        .clki      (osc_clk),
        .clko_fast (sys_clk_fast),
        .clko_slow (sys_clk_slow),
        .locked    (pll_locked)
    );

    wire unused_clk_ext = clk_ext;

    // ---- Reset (one counter per domain; both gated by PLL lock) ----
    wire reset_button = ~btn_mecha[1];

    reg  [1:0] reset_sync_fast    = 2'b11;
    reg  [7:0] reset_counter_fast = 8'd0;
    wire       reset_request_fast = reset_sync_fast[1];
    wire       resetn_fast        = (&reset_counter_fast) & pll_locked;
    always @(posedge sys_clk_fast) begin
        reset_sync_fast <= {reset_sync_fast[0], reset_button};
        if (reset_request_fast)
            reset_counter_fast <= 8'd0;
        else if (!(&reset_counter_fast))
            reset_counter_fast <= reset_counter_fast + 8'd1;
    end

    reg  [1:0] reset_sync_slow    = 2'b11;
    reg  [7:0] reset_counter_slow = 8'd0;
    wire       reset_request_slow = reset_sync_slow[1];
    wire       resetn_slow        = (&reset_counter_slow) & pll_locked;
    always @(posedge sys_clk_slow) begin
        reset_sync_slow <= {reset_sync_slow[0], reset_button};
        if (reset_request_slow)
            reset_counter_slow <= 8'd0;
        else if (!(&reset_counter_slow))
            reset_counter_slow <= reset_counter_slow + 8'd1;
    end

    // ============================================================
    //                       FAST DOMAIN
    // ============================================================

    // ---- btn_mecha[0] (aspect cycle) — fast-domain debounced ----
    wire grey_press;
    btn_debounce #(.WIDTH(1), .STABLE_CYCLES(4096)) u_deb_grey (
        .clk(sys_clk_fast), .resetn(resetn_fast),
        .btn_n(btn_mecha[0]), .btn_press(grey_press)
    );

    reg grey_press_d;
    always @(posedge sys_clk_fast) grey_press_d <= grey_press;
    wire grey_press_edge = grey_press & ~grey_press_d;

    reg [1:0] aspect_idx;
    always @(posedge sys_clk_fast) begin
        if (!resetn_fast)
            aspect_idx <= 2'b10;     // CIRCLE on reset
        else if (grey_press_edge)
            aspect_idx <= (aspect_idx == 2'b10) ? 2'b00 : aspect_idx + 2'b01;
    end

    // ---- image_stretch + oled_gc9a01 ----
    wire [15:0] gc9a01_pixel_index;
    wire [12:0] image_idx;
    wire        valid_pixel;
    image_stretch u_stretch (
        .clk         (sys_clk_fast),
        .resetn      (resetn_fast),
        .pixel_index (gc9a01_pixel_index),
        .mode        (aspect_idx),
        .image_idx   (image_idx),
        .valid_pixel (valid_pixel)
    );

    wire [15:0] fb_pixel_data;
    wire        oled_frame_done;     // direct from oled_gc9a01.frame_done

    // valid_pixel + frame buffer dout share the same 1-cycle BRAM-read latency,
    // so register valid_pixel once to align with fb_pixel_data.
    reg valid_pixel_r;
    always @(posedge sys_clk_fast) valid_pixel_r <= valid_pixel;
    wire [15:0] pixel_data_masked = valid_pixel_r ? fb_pixel_data : 16'h0000;

    wire init_done, streaming;
    oled_gc9a01 #(
        .CLK_HZ           (CLK_FAST_HZ),
        .INIT_SPI_CLK_DIV (8'd4)
    ) u_oled (
        .clk         (sys_clk_fast),
        .resetn      (resetn_fast),
        .pixel_index (gc9a01_pixel_index),
        .pixel_data  (pixel_data_masked),
        .oled_scl    (oled_scl),
        .oled_sda    (oled_sda),
        .oled_dc     (oled_dc),
        .oled_cs     (oled_cs),
        .oled_rst    (oled_rst),
        .init_done   (init_done),
        .streaming   (streaming),
        .frame_done  (oled_frame_done)
    );

    // ============================================================
    //                       SLOW DOMAIN
    // ============================================================

    // ---- Buttons (slow-domain debounce — feeds Top_Student) ----
    wire [4:0] btn_press_slow;
    btn_debounce #(.WIDTH(5), .STABLE_CYCLES(2048)) u_deb_slow (
        .clk(sys_clk_slow), .resetn(resetn_slow),
        .btn_n(btn), .btn_press(btn_press_slow)
    );

    // ---- btn_mecha[1] press → task_idx (no reset, sync'd to slow) ----
    reg btn1_d, btn1_dd;
    always @(posedge sys_clk_slow) begin
        btn1_d  <= btn_mecha[1];
        btn1_dd <= btn1_d;
    end
    wire mecha1_press_edge = btn1_dd & ~btn1_d;   // falling edge = press

    reg [1:0] task_idx = 2'b00;
    always @(posedge sys_clk_slow) begin
        if (mecha1_press_edge)
            task_idx <= task_idx + 2'b01;
    end

    wire [15:0] sw_value = {12'b0,
                            (task_idx == 2'd3),
                            (task_idx == 2'd2),
                            (task_idx == 2'd1),
                            (task_idx == 2'd0)};

    // ---- scan_idx: walks 0..6143 to drive Top_Student rendering ----
    reg  [12:0] scan_idx;
    always @(posedge sys_clk_slow) begin
        if (!resetn_slow)
            scan_idx <= 13'd0;
        else
            scan_idx <= (scan_idx == 13'd6143) ? 13'd0 : scan_idx + 13'd1;
    end
    wire scan_done = (scan_idx == 13'd6143);

    // ---- EE2026 Top_Student in slow domain ----
    wire [15:0] ee_led;
    wire [6:0]  ee_seg;
    wire        ee_dp;
    wire [3:0]  ee_an;
    wire [15:0] ee_pixel_data;
    Top_Student u_ee2026 (
        .clk              (sys_clk_slow),
        .btnC             (btn_press_slow[2]),
        .btnU             (btn_press_slow[1]),
        .btnL             (btn_press_slow[0]),
        .btnR             (btn_press_slow[4]),
        .btnD             (btn_press_slow[3]),
        .sw               (sw_value),
        .led              (ee_led),
        .seg              (ee_seg),
        .dp               (ee_dp),
        .an               (ee_an),
        .oled_pixel_index (scan_idx),
        .oled_pixel_data  (ee_pixel_data)
    );

    // ============================================================
    //                  CDC: double-buffered frame buffer
    // ============================================================
    frame_buffer #(.DEPTH(6144), .ADDR_W(13), .DATA_W(16)) u_fb (
        .clk_w      (sys_clk_slow),
        .we         (1'b1),
        .addr_w     (scan_idx),
        .din        (ee_pixel_data),
        .scan_done  (scan_done),
        .clk_r      (sys_clk_fast),
        .addr_r     (image_idx),
        .dout       (fb_pixel_data),
        .frame_done (oled_frame_done)
    );

    // ---- LEDs ----
    // [7] init_done | [6] streaming | [5:4] aspect_idx | [3:2] task_idx
    // [1:0] EE2026 led low bits
    assign led = {init_done, streaming, aspect_idx, task_idx, ee_led[1:0]};

    // Suppress unused warnings on EE2026 7-seg outputs (greybadge has no 7-seg)
    wire unused_seg = |ee_seg | ee_dp | |ee_an;

    assign interconnect = 8'bz;
    assign pmod_j1      = 8'bz;
    assign pmod_j2      = 8'bz;
    assign s            = 5'bz;
endmodule
