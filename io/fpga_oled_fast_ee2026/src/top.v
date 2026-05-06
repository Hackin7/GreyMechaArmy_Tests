// top.v — bridge between the EE2026 Top_Student design and the greybadge
// hardware. Top_Student produces 96×64 pixel data; image_stretch maps the
// GC9A01's 240×240 pixel index to a 96×64 image_idx, fed back into
// Top_Student. The resulting pixel_data drives our oled_gc9a01.
//
// Button mapping:
//   btn[0..4]    → btnC, btnU, btnL, btnR, btnD (forwarded into EE2026)
//   btn_mecha[0] (was btn_grey, D12) — press to cycle aspect mode
//                                       (FULL → ASPECT → CIRCLE → FULL ...)
//   btn_mecha[1] (was btn_rst,  C12) — held LOW = system reset; each press
//                                       also advances task selection
//                                       (A → B → C → D → A ...). task_idx
//                                       is *not* reset by resetn so the
//                                       task choice survives the reset.
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
    localparam integer CLK_HZ = 12900000;

    // ---- Clock: OSCG /24 (~12.9 MHz nominal, 14.85 MHz worst-case at +15%).
    // /16 (~19.4 MHz) was tight before but tipped over after the
    // adaptor_task_b is_green_border function got heavier. /24 gives room.
    // Frame at 12.9 MHz / 2 SCLK / 32 cycles per pixel ≈ 143 ms (~7 fps).
    wire osc_clk;
    defparam OSCI1.DIV = "24";
    OSCG OSCI1 (.OSC(osc_clk));

    wire sys_clk = osc_clk;
    wire pll_locked = 1'b1;

    wire unused_clk_ext = clk_ext;

    // ---- Reset (btn_mecha[1] held LOW; sync + counter; gated by PLL lock) ----
    wire reset_button = ~btn_mecha[1];
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

    // ---- Buttons (debounced) ----
    wire [4:0] btn_press;
    wire       grey_press;
    btn_debounce #(.WIDTH(5), .STABLE_CYCLES(4096)) u_deb (
        .clk(sys_clk), .resetn(resetn), .btn_n(btn), .btn_press(btn_press)
    );
    btn_debounce #(.WIDTH(1), .STABLE_CYCLES(4096)) u_grey (
        .clk(sys_clk), .resetn(resetn), .btn_n(btn_mecha[0]), .btn_press(grey_press)
    );

    // ---- Aspect mode cycle on btn_mecha[0] press edge ----
    // grey_press is debounced. Detect rising edge → cycle through 3 modes.
    reg  grey_press_d;
    always @(posedge sys_clk) grey_press_d <= grey_press;
    wire grey_press_edge = grey_press & ~grey_press_d;

    reg [1:0] aspect_idx;
    always @(posedge sys_clk) begin
        if (!resetn)
            aspect_idx <= 2'b10;
        else if (grey_press_edge)
            aspect_idx <= (aspect_idx == 2'b10) ? 2'b00 : aspect_idx + 2'b01;
    end

    // ---- Task cycle on btn_mecha[1] press edge ----
    // task_idx is NOT in any reset block. Initial value 0 from FPGA boot.
    // It increments on the falling edge of btn_mecha[1] (button pressed) so
    // the count survives the reset that the same button press also triggers.
    reg  btn_mecha1_sync_d;
    reg  btn_mecha1_sync_dd;
    always @(posedge sys_clk) begin
        btn_mecha1_sync_d  <= btn_mecha[1];
        btn_mecha1_sync_dd <= btn_mecha1_sync_d;
    end
    // Falling edge of active-low button = pressed.
    wire mecha1_press_edge = btn_mecha1_sync_dd & ~btn_mecha1_sync_d;

    reg [1:0] task_idx = 2'b00;
    always @(posedge sys_clk) begin
        if (mecha1_press_edge)
            task_idx <= task_idx + 2'b01;
    end

    // sw_value = one-hot(task_idx) on bits [3:0]; sw[3:0] picks tasks A..D.
    wire [15:0] sw_value = {12'b0,
                            (task_idx == 2'd3),
                            (task_idx == 2'd2),
                            (task_idx == 2'd1),
                            1};//(task_idx == 2'd0)};

    // ---- Stretcher (mode driven by aspect_idx) ----
    wire [15:0] gc9a01_pixel_index;
    wire [12:0] image_idx;
    wire        valid_pixel;
    image_stretch u_stretch (
        .clk         (sys_clk),
        .resetn      (resetn),
        .pixel_index (gc9a01_pixel_index),
        .mode        (aspect_idx),
        .image_idx   (image_idx),
        .valid_pixel (valid_pixel)
    );

    // ---- EE2026 Top_Student ----
    wire [15:0] ee_led;
    wire [6:0]  ee_seg;
    wire        ee_dp;
    wire [3:0]  ee_an;
    wire [15:0] ee_pixel_data;
    Top_Student u_ee2026 (
        .clk              (sys_clk),
        .btnC             (btn_press[2]),
        .btnU             (btn_press[1]),
        .btnL             (btn_press[0]),
        .btnR             (btn_press[4]),
        .btnD             (btn_press[3]),
        .sw               (sw_value),
        .led              (ee_led),
        .seg              (ee_seg),
        .dp               (ee_dp),
        .an               (ee_an),
        .oled_pixel_index (image_idx),
        .oled_pixel_data  (ee_pixel_data)
    );

    // Pipeline ee_pixel_data + valid_pixel by 1 cycle so they line up with
    // what oled_gc9a01 sees on the BRAM-style 1-cycle latency path.
    reg [15:0] pixel_data;
    reg        valid_pixel_r;
    always @(posedge sys_clk) begin
        pixel_data    <= ee_pixel_data;
        valid_pixel_r <= valid_pixel;
    end

    // Mask the letterbox region with black (only matters in ASPECT/CIRCLE).
    wire [15:0] pixel_data_masked = valid_pixel_r ? pixel_data : 16'h0000;

    // ---- OLED driver ----
    wire init_done, streaming;
    oled_gc9a01 #(
        .CLK_HZ           (CLK_HZ),
        .INIT_SPI_CLK_DIV (8'd4)
    ) u_oled (
        .clk         (sys_clk),
        .resetn      (resetn),
        .pixel_index (gc9a01_pixel_index),
        .pixel_data  (pixel_data_masked),
        .oled_scl    (oled_scl),
        .oled_sda    (oled_sda),
        .oled_dc     (oled_dc),
        .oled_cs     (oled_cs),
        .oled_rst    (oled_rst),
        .init_done   (init_done),
        .streaming   (streaming)
    );

    // ---- LEDs ----
    // [7] init_done | [6] streaming | [5:4] aspect_idx | [3:2] task_idx
    // [1:0] EE2026 led low bits (mostly zero)
    assign led = {init_done, streaming, aspect_idx, task_idx, ee_led[1:0]};

    // Suppress unused warnings on EE2026 7-seg outputs (greybadge has no 7-seg)
    wire unused_seg = |ee_seg | ee_dp | |ee_an;

    assign interconnect = 8'bz;
    assign pmod_j1      = 8'bz;
    assign pmod_j2      = 8'bz;
    assign s            = 5'bz;
endmodule
