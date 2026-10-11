module gc9a01_window_init (
    input wire clk, input wire resetn, input wire rearm,
    output wire init_done, output wire ramwr_pulse,
    output wire sclk, output wire mosi, output wire dc,
    output wire cs_n, output wire rst_n
);
    // Match the panel-proven init clock.  Divider 0 is unreliable with the
    // byte SPI master on this board; divider 4 is a stable 7.5 MHz at the
    // 75 MHz panel clock.
    oled_init #(.CLK_HZ(75000000), .SPI_CLK_DIV(8'd4)) impl (
        .clk(clk), .resetn(resetn), .init_done(init_done),
        .ramwr_pulse(ramwr_pulse), .rearm(rearm), .sclk(sclk),
        .mosi(mosi), .dc(dc), .cs(cs_n), .rst_n(rst_n)
    );
endmodule
