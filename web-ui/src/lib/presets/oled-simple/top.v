// Minimal GC9A01 starter: edit pixel_data below to change the RGB565 color.
// btn[6] is active-low reset; the other buttons are available for your logic.
module top (
    input  wire       clk_ext,
    input  wire [6:0] btn,
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

    // On-chip oscillator /6 -> PLL -> nominal 75 MHz system clock.
    wire osc_clk;
    defparam OSCI1.DIV = "6";
    OSCG OSCI1 (.OSC(osc_clk));

    wire sys_clk, pll_locked;
    ecp5_oled_pll u_pll (
        .clki(osc_clk), .clko(sys_clk), .locked(pll_locked)
    );
    wire unused_clk_ext = clk_ext;

    // Start in reset, synchronize the button, and wait for PLL lock.
    wire reset_button = ~btn[6];
    reg [1:0] reset_sync = 2'b11;
    reg [7:0] reset_counter = 0;
    wire resetn = (&reset_counter) & pll_locked;
    always @(posedge sys_clk) begin
        reset_sync <= {reset_sync[0], reset_button};
        if (reset_sync[1])
            reset_counter <= 0;
        else if (!(&reset_counter))
            reset_counter <= reset_counter + 1;
    end

    // RGB565: 5 red bits, 6 green bits, 5 blue bits. 16'h07E0 is green.
    // pixel_index is the current linear pixel address (0..57599).
    wire [15:0] pixel_index;
    wire [15:0] pixel_data;
    assign pixel_data = 16'h07E0;

    wire init_done, streaming;
    oled_gc9a01 #(
        .CLK_HZ(CLK_HZ), .INIT_SPI_CLK_DIV(8'd4)
    ) u_oled (
        .clk(sys_clk),
        .resetn(resetn),
        .pixel_index(pixel_index),
        .pixel_data(pixel_data),
        .oled_scl(oled_scl),
        .oled_sda(oled_sda),
        .oled_dc(oled_dc),
        .oled_cs(oled_cs),
        .oled_rst(oled_rst),
        .init_done(init_done),
        .streaming(streaming)
    );

    // LED[7:2]: initialized, streaming, CS, DC, panel reset, PLL lock.
    assign led = {init_done, streaming, oled_cs, oled_dc,
                  oled_rst, pll_locked, 2'b00};

    assign interconnect = 8'bz;
    assign pmod_j1 = 8'bz;
    assign pmod_j2 = 8'bz;
    assign s = 5'bz;
endmodule
