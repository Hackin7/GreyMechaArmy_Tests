// tb_oled_init.v — drives oled_init standalone, sniffs the SPI bytes it
// emits, prints them with CMD/DAT classification. Manual verification:
// compare the dump against scripts/gen_gc9a01_init_rom.py.

`timescale 1ns / 1ps

module tb_oled_init;
    reg clk = 1'b0;
    always #5 clk = ~clk;            // 100 MHz simulated

    reg resetn = 1'b0;
    initial #100 resetn = 1'b1;

    reg rearm = 1'b0;

    wire init_done, ramwr_pulse;
    wire sclk, mosi, dc, cs, rst_n;

    oled_init #(.CLK_HZ(100_000), .SPI_CLK_DIV(8'd1)) dut (
        .clk         (clk),
        .resetn      (resetn),
        .init_done   (init_done),
        .ramwr_pulse (ramwr_pulse),
        .rearm       (rearm),
        .sclk        (sclk),
        .mosi        (mosi),
        .dc          (dc),
        .cs          (cs),
        .rst_n       (rst_n)
    );

    // Skip init-ROM pauses (SLPOUT, etc.) so simulation completes quickly.
    // Pauses don't affect SPI byte correctness — only timing between bytes.
    // S_INIT_PAUSE = 4'd6 in oled_init.v. The pause FSM only exits when
    // pause_cnt == 0, so force to 0 (not 1) to fall straight through.
    always @(*) begin
        if (dut.st == 4'd6)
            force dut.pause_cnt = 24'd0;
        else
            release dut.pause_cnt;
    end

    // SPI byte sniffer: detect rising sclk while !cs, capture mosi into a
    // shift register; on every 8th bit, print the assembled byte with the
    // dc level (CMD vs DAT). Reset the bit counter on cs deassert.
    reg sclk_d = 1'b0;
    always @(posedge clk) sclk_d <= sclk;
    wire sclk_rising = sclk & ~sclk_d;

    reg [7:0] byte_buf = 8'd0;
    reg [3:0] bit_cnt  = 4'd0;

    integer byte_count = 0;

    always @(posedge clk) begin
        if (cs) begin
            bit_cnt <= 4'd0;
        end else if (sclk_rising) begin
            if (bit_cnt == 4'd7) begin
                $display("[%6t] %s 0x%02h", $time,
                         dc ? "DAT" : "CMD",
                         {byte_buf[6:0], mosi});
                byte_count <= byte_count + 1;
                bit_cnt <= 4'd0;
            end else begin
                byte_buf <= {byte_buf[6:0], mosi};
                bit_cnt <= bit_cnt + 4'd1;
            end
        end
    end

    initial begin
        $dumpfile("build/init.vcd");
        $dumpvars(0, tb_oled_init);

        wait (init_done);
        $display("[%6t] === INIT DONE (%0d bytes sent) ===",
                 $time, byte_count);

        #1000;
        rearm = 1'b1;
        wait (ramwr_pulse);
        $display("[%6t] === RAMWR PULSE on rearm ===", $time);
        rearm = 1'b0;

        #1000;
        $finish;
    end

    initial begin
        #50_000_000;
        $display("[%6t] === WATCHDOG TIMEOUT (sent %0d bytes) ===",
                 $time, byte_count);
        $finish;
    end
endmodule
