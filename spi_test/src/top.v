module top(
    input clk_ext, input [4:0] btn, output [7:0] led, 
    inout [7:0] interconnect, 
    inout [7:0] pmod_j1, inout [7:0] pmod_j2,
    output oled_scl,
    output oled_sda,
    output oled_dc,
    output oled_cs,
    output oled_rst,
    inout [4:0] s // secret pins
);
    /// Internal Configuration ///////////////////////////////////////////
    wire clk_int;        // Internal OSCILLATOR clock
    defparam OSCI1.DIV = "3"; // Info: Max frequency for clock '$glbnet$clk': 162.00 MHz (PASS at 103.34 MHz)
    OSCG OSCI1 (.OSC(clk_int));

    wire clk = clk_int;
    localparam CLK_FREQ = 103_340_000; // EXT CLK

    // External Oscillator Easter egg /////
    reg clk_ext_soldered = 0;
    always @ (posedge clk_ext) begin clk_ext_soldered <= 1; end

    // Clock Configuration
    reg [31:0] clk_stepdown_counter = 0;
    reg [31:0] clk_stepdown_count_val = 5;
    reg clk_stepdown;
    always @ (posedge clk) begin
        clk_stepdown_counter <= clk_stepdown_counter + 1;
        if (clk_stepdown_counter >= clk_stepdown_count_val) begin
            clk_stepdown <= ~clk_stepdown;
            clk_stepdown_counter <= 0;
        end
    end

    assign led = 8'b11111111;
    

    // Instantiate the gc9a01_driver module
    spi_master #(
        .CLK_FREQ       (CLK_FREQ),   // System clock frequency (e.g., 50 MHz)
        .SPI_FREQ       (10_000_000),   // SPI clock frequency (e.g., 10 MHz)
        .SCREEN_WIDTH   (240),          // Screen width
        .SCREEN_HEIGHT  (240)           // Screen height
    ) gc9a01_driver_inst (
        .clk            (clk),
        .reset_n        (1'b1),

        .spi_clk        (oled_scl),
        .spi_mosi       (oled_sda),
        .spi_cs_n       (oled_cs),
        .lcd_dc         (oled_dc),
        .lcd_rst_n      (oled_rst),

        .pixel_data     (16'hFFFF),
        .pixel_valid    (1'b1),
        //.pixel_ready    (o_pixel_ready),

        .start_init     (1'b1),
        .start_display  (1'b1),
        //.init_done      (o_init_done),
        //.display_busy   (o_display_busy),

        //.pixel_count    (o_pixel_count)
    );

endmodule

