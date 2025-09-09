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

    //assign led = 8'b11111111;
    assign led = {3'b000, ~btn};

    // Instantiate the spi_master module
    gc9a01 uut (
        .clk(clk),
        .rst_n(btn[0]),
        .sclk(oled_scl),
        .mosi(oled_sda),
        .ncs(oled_cs),
        .dc(oled_dc)
        //.done(done)
    );

    /*
    spi_master dut (
        .clk(clk),
        .rst_n(~btn[0]),
        .data_in(8'hFA),
        .start_transfer(~btn[1]),
        .transfer_done(led[0]),
        .sclk(oled_scl),
        .mosi(oled_sda),
        .ncs(oled_cs)
        //.lcd_dc         (oled_dc),
    );
    */
endmodule

