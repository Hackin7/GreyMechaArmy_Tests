// top.v — minimal greybadge build that drives the GC9A01 OLED with two
// pixel sources: the raycasting demo and the stonks bitmap.
//
//   Slow domain (sys_clk_slow ≈ 12.5 MHz):
//     • raycasting   — produces oled_pixel_data given (xpos, ypos)
//     • stonks_rom   — static 96x64 RGB565 lookup
//     • scan_idx     — walks 0..6143 to address the back buffer
//   Fast domain (sys_clk_fast = 75 MHz):
//     • oled_gc9a01  — runs the OLED at full streaming rate
//     • image_stretch — converts 240x240 OLED indices to 96x64 image_idx
//     • frame_buffer read
//
// Mode selection:
//   btn_mecha[1] press → toggles between raycasting and stonks.
//
// Buttons:
//   btn[0..4]    → btnL/U/C/D/R (raw level) into raycasting
//   btn_mecha[0] (D12) — press to cycle aspect mode
//   btn_mecha[1] (C12) — held LOW = system reset; press also toggles mode.
module top (
    input  wire       clk_ext,
    input  wire [4:0] btn,
    input  wire [1:0] btn_mecha,
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

    // ---- Clocks: OSCG /6 → PLL → 75 MHz fast + 12.5 MHz slow ----
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

    // ---- Reset ----
    wire reset_button = ~btn_mecha[1];

    reg  [1:0] reset_sync_fast    = 2'b11;
    reg  [7:0] reset_counter_fast = 8'd0;
    wire       resetn_fast        = (&reset_counter_fast) & pll_locked;
    always @(posedge sys_clk_fast) begin
        reset_sync_fast <= {reset_sync_fast[0], reset_button};
        if (reset_sync_fast[1])
            reset_counter_fast <= 8'd0;
        else if (!(&reset_counter_fast))
            reset_counter_fast <= reset_counter_fast + 8'd1;
    end

    reg  [1:0] reset_sync_slow    = 2'b11;
    reg  [7:0] reset_counter_slow = 8'd0;
    wire       resetn_slow        = (&reset_counter_slow) & pll_locked;
    always @(posedge sys_clk_slow) begin
        reset_sync_slow <= {reset_sync_slow[0], reset_button};
        if (reset_sync_slow[1])
            reset_counter_slow <= 8'd0;
        else if (!(&reset_counter_slow))
            reset_counter_slow <= reset_counter_slow + 8'd1;
    end

    // ============================================================
    //                       FAST DOMAIN
    // ============================================================

    // ---- btn_mecha[0] aspect cycle ----
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
    wire        oled_frame_done;

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

    // ---- btn_mecha[1] press → mode toggle (no reset) ----
    reg btn1_d, btn1_dd;
    always @(posedge sys_clk_slow) begin
        btn1_d  <= btn_mecha[1];
        btn1_dd <= btn1_d;
    end
    wire mecha1_press_edge = btn1_dd & ~btn1_d;

    // mode_idx: 0 = raycasting, 1 = stonks
    reg mode_idx = 1'b0;
    always @(posedge sys_clk_slow) begin
        if (mecha1_press_edge)
            mode_idx <= ~mode_idx;
    end

    // ---- Raw button levels (active high) sync'd to slow clk for raycasting ----
    wire [4:0] btn_active_h = ~btn;
    reg  [4:0] btn_lvl_d, btn_lvl;
    always @(posedge sys_clk_slow) begin
        btn_lvl_d <= btn_active_h;
        btn_lvl   <= btn_lvl_d;
    end

    // ---- scan_idx + xpos/ypos counters (avoid `% 96` / `/ 96` in raycasting) ----
    reg  [12:0] scan_idx;
    reg  [7:0]  oled_xpos;
    reg  [7:0]  oled_ypos;
    always @(posedge sys_clk_slow) begin
        if (!resetn_slow) begin
            scan_idx  <= 13'd0;
            oled_xpos <= 8'd0;
            oled_ypos <= 8'd0;
        end else if (scan_idx == 13'd6143) begin
            scan_idx  <= 13'd0;
            oled_xpos <= 8'd0;
            oled_ypos <= 8'd0;
        end else begin
            scan_idx <= scan_idx + 13'd1;
            if (oled_xpos == 8'd95) begin
                oled_xpos <= 8'd0;
                oled_ypos <= oled_ypos + 8'd1;
            end else begin
                oled_xpos <= oled_xpos + 8'd1;
            end
        end
    end
    wire scan_done = (scan_idx == 13'd6143);

    // ---- Raycasting ----
    wire [15:0] ray_pixel_data;
    raycasting u_ray (
        .reset              (~resetn_slow),
        .clk                (sys_clk_slow),
        .btnC               (btn_lvl[2]),
        .btnU               (btn_lvl[3]),
        .btnL               (btn_lvl[0]),
        .btnR               (btn_lvl[4]),
        .btnD               (btn_lvl[1]),
        .seg                (),
        .dp                 (),
        .an                 (),
        .oled_pixel_index   (scan_idx),
        .oled_pixel_data    (ray_pixel_data),
        .oled_xpos          (oled_xpos),
        .oled_ypos          (oled_ypos),
        .text_lines         (),
        .text_colour        (),
        .mouse_xpos         (12'd0),
        .mouse_ypos         (12'd0),
        .mouse_zpos         (4'd0),
        .mouse_left_click   (1'b0),
        .mouse_middle_click (1'b0),
        .mouse_right_click  (1'b0),
        .mouse_new_event    (1'b0)
    );

    // ---- Stonks ROM ----
    reg [15:0] stonks_rom [0:6143];
    initial $readmemh("src/raycasting/stonks.mem", stonks_rom);
    reg [15:0] stonks_pixel_data;
    always @(posedge sys_clk_slow) stonks_pixel_data <= stonks_rom[scan_idx];

    // ---- Slow-domain pixel mux ----
    wire [15:0] slow_pixel_data = mode_idx ? stonks_pixel_data : ray_pixel_data;

    // ============================================================
    //                  CDC: double-buffered frame buffer
    // ============================================================
    frame_buffer #(.DEPTH(6144), .ADDR_W(13), .DATA_W(16)) u_fb (
        .clk_w      (sys_clk_slow),
        .we         (1'b1),
        .addr_w     (scan_idx),
        .din        (slow_pixel_data),
        .scan_done  (scan_done),
        .clk_r      (sys_clk_fast),
        .addr_r     (image_idx),
        .dout       (fb_pixel_data),
        .frame_done (oled_frame_done)
    );

    // ---- LEDs ----
    // [7] init_done | [6] streaming | [5:4] aspect_idx | [3] mode_idx
    // [2:0] reserved
    assign led = {init_done, streaming, aspect_idx, mode_idx, 3'b000};

    assign interconnect = 8'bz;
    assign pmod_j1      = 8'bz;
    assign pmod_j2      = 8'bz;
    assign s            = 5'bz;
endmodule
