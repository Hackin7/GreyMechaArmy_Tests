// top.v — fast streaming GC9A01 driver. The OLED driver itself is wrapped
// in oled_gc9a01.v; this top only handles board-level concerns: clock/PLL,
// reset, buttons, image BRAM + stretcher, and the pixel-source mux.
//
// Image-button modes (priority high → low): grey > btn[4] > btn[3] >
// btn[2] > btn[1] > btn[0]
//   grey   → solid 16'hFFE0  (overrides others)
//   btn[4] → solid pink
//   btn[3] → image at 2× scale (192×128 centered, fits inside the GC9A01 circle)
//   btn[2] → image aspect-correct (240×160 with 40px letterbox top/bottom)
//   btn[1] → solid red
//   btn[0] → image full-stretch (240×240, distorts aspect)
//   none   → solid white
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
    localparam integer IMG_W  = 96;
    localparam integer IMG_H  = 64;

    // ---- Clock: OSCG /6 (~50 MHz) → PLL → 75 MHz ----
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

    // ---- Image BRAM + stretcher ----
    reg [15:0] image_memory [0:IMG_W*IMG_H - 1];
    initial $readmemh("stonks.mem", image_memory);

    wire [15:0] pixel_index;
    wire [1:0]  stretch_mode = btn_press[3] ? 2'b10 :    // CIRCLE
                               btn_press[2] ? 2'b01 :    // ASPECT
                                              2'b00;    // FULL
    wire [12:0] image_idx;
    wire        valid_pixel;
    image_stretch u_stretch (
        .clk         (sys_clk),
        .resetn      (resetn),
        .pixel_index (pixel_index),
        .mode        (stretch_mode),
        .image_idx   (image_idx),
        .valid_pixel (valid_pixel)
    );

    reg [15:0] image_pixel_data_r;
    reg        valid_pixel_r;
    always @(posedge sys_clk) begin
        image_pixel_data_r <= image_memory[image_idx];
        valid_pixel_r      <= valid_pixel;
    end

    // ---- Pixel source mux (registered) ----
    reg [15:0] pixel_data;
    always @(posedge sys_clk) begin
        if      (grey_press)   pixel_data <= 16'hFFE0;
        else if (btn_press[4]) pixel_data <= 16'hFE19;
        else if (btn_press[3]) pixel_data <= valid_pixel_r ? image_pixel_data_r : 16'h0000;
        else if (btn_press[2]) pixel_data <= valid_pixel_r ? image_pixel_data_r : 16'h0000;
        else if (btn_press[1]) pixel_data <= 16'hF800;
        else if (btn_press[0]) pixel_data <= image_pixel_data_r;
        else                   pixel_data <= 16'hFFFF;
    end

    // ---- OLED driver (init + stream + sequencer + pin mux all in one) ----
    wire init_done, streaming;
    oled_gc9a01 #(
        .CLK_HZ           (CLK_HZ),
        .INIT_SPI_CLK_DIV (8'd4)
    ) u_oled (
        .clk         (sys_clk),
        .resetn      (resetn),
        .pixel_index (pixel_index),
        .pixel_data  (pixel_data),
        .oled_scl    (oled_scl),
        .oled_sda    (oled_sda),
        .oled_dc     (oled_dc),
        .oled_cs     (oled_cs),
        .oled_rst    (oled_rst),
        .init_done   (init_done),
        .streaming   (streaming)
    );

    // ---- Status LEDs ----
    // LED[7] init_done | [6] streaming | [5] oled_cs | [4] oled_dc
    // LED[3] oled_rst  | [2] pll_locked | [1] grey_press | [0] btn[0]
    assign led = {init_done, streaming, oled_cs, oled_dc,
                  oled_rst, pll_locked, grey_press, btn_press[0]};

    // Non-OLED inout pins parked at high-Z.
    assign interconnect = 8'bz;
    assign pmod_j1      = 8'bz;
    assign pmod_j2      = 8'bz;
    assign s            = 5'bz;
endmodule
