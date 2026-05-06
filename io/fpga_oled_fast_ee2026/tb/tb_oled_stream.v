// tb_oled_stream.v — drives oled_stream with synthetic pixel_data
// (= pixel_index, registered). Sniffs mosi while sclk_active, packs
// 16-bit words. Expected sequence: 0x0000, 0x0001, 0x0002, ...

`timescale 1ns / 1ps

module tb_oled_stream;
    reg clk = 1'b0;
    always #5 clk = ~clk;            // 100 MHz simulated

    reg resetn = 1'b0;
    reg enable = 1'b0;
    initial begin
        #100 resetn = 1'b1;
        #100 enable = 1'b1;
    end

    wire [15:0] pixel_index;
    reg  [15:0] pixel_data = 16'd0;

    // Mimic the BRAM read latency in top.v: pixel_data trails pixel_index
    // by one cycle. With this generator, pixel N has value N.
    always @(posedge clk) pixel_data <= pixel_index;

    wire sclk, mosi, cs, dc, frame_done;

    oled_stream dut (
        .clk         (clk),
        .resetn      (resetn),
        .enable      (enable),
        .pixel_index (pixel_index),
        .pixel_data  (pixel_data),
        .sclk        (sclk),
        .mosi        (mosi),
        .cs          (cs),
        .dc          (dc),
        .frame_done  (frame_done)
    );

    // Pixel sniffer: now sclk is a real toggling signal, sample on its
    // rising edge (same convention the slave panel uses).
    reg [15:0] word_buf = 16'd0;
    reg [4:0]  word_bit_cnt = 5'd0;
    integer    pixel_print_count = 0;

    always @(posedge sclk) begin
        if (!cs) begin
            if (word_bit_cnt == 5'd15) begin
                $display("[%6t] PIX %0d: 0x%04h (streamer.pixel_index=%0d)",
                         $time, pixel_print_count,
                         {word_buf[14:0], mosi}, pixel_index);
                pixel_print_count <= pixel_print_count + 1;
                word_bit_cnt <= 5'd0;
            end else begin
                word_buf <= {word_buf[14:0], mosi};
                word_bit_cnt <= word_bit_cnt + 5'd1;
            end
        end
    end

    initial begin
        $dumpfile("build/stream.vcd");
        $dumpvars(0, tb_oled_stream);

        wait (enable);
        #5000;
        $display("[%6t] === STOPPING (sniffed %0d pixels) ===",
                 $time, pixel_print_count);
        $finish;
    end

    initial begin
        #1_000_000;
        $display("[%6t] === WATCHDOG TIMEOUT ===", $time);
        $finish;
    end
endmodule
