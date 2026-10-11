`timescale 1ns/1ps
module tb_panel_colours #(parameter SWAP_RB = 1);
    reg clk = 0, resetn = 0, line_ready = 0;
    always #5 clk = ~clk;
    wire line_done, frame_done, rd_bank, sclk, mosi, dc, cs_n;
    wire [7:0] rd_addr;
    reg [15:0] rd_data = 0;
    reg [15:0] serial_word = 0;
    integer bits = 0, words = 0, clear_words = 0;
    reg cleared = 0;

    function [15:0] logical_colour(input integer pixel);
        case (pixel % 6)
            0: logical_colour = 16'hf800; // red
            1: logical_colour = 16'h07e0; // green
            2: logical_colour = 16'h001f; // blue
            3: logical_colour = 16'hffff; // white
            4: logical_colour = 16'ha145; // brown: R=20 G=10 B=5
            5: logical_colour = 16'h0000; // black
        endcase
    endfunction

    // Independent, literal expected wire words, including asymmetric brown.
    function [15:0] wire_colour(input integer pixel);
        if (!SWAP_RB) wire_colour = logical_colour(pixel);
        else case (pixel % 6)
            0: wire_colour = 16'h001f;
            1: wire_colour = 16'h07e0;
            2: wire_colour = 16'hf800;
            3: wire_colour = 16'hffff;
            4: wire_colour = 16'h2954;
            5: wire_colour = 16'h0000;
        endcase
    endfunction

    // Match the synchronous line-buffer latency on the real panel path.
    always @(posedge clk) rd_data <= logical_colour(rd_addr);
    gc9a01_line_stream #(.SWAP_RB(SWAP_RB)) dut (
        .clk(clk), .resetn(resetn), .enable(1'b1),
        .line_ready(line_ready), .line_bank(1'b0), .line_number(8'd0),
        .line_done(line_done), .rd_addr(rd_addr), .rd_bank(rd_bank),
        .rd_data(rd_data), .frame_done(frame_done),
        .sclk(sclk), .mosi(mosi), .dc(dc), .cs_n(cs_n)
    );

    always @(posedge sclk) begin
        if (!cs_n) begin
            if (!dc) $fatal(1, "pixel sent as command");
            serial_word = {serial_word[14:0], mosi};
            bits = bits + 1;
            if (bits == 16) begin
                bits = 0;
                if (!cleared) begin
                    if (serial_word !== 16'hffff)
                        $fatal(1, "clear frame not white");
                    clear_words = clear_words + 1;
                end else begin
                    if (serial_word !== wire_colour(words % 160))
                        $fatal(1, "pixel %0d wire=%h expected=%h", words,
                               serial_word, wire_colour(words % 160));
                    words = words + 1;
                end
            end
        end
    end

    task send_line;
        begin
            @(negedge clk); line_ready = 1;
            wait(line_done);
            @(negedge clk); line_ready = 0;
            repeat(4) @(negedge clk);
        end
    endtask

    initial begin
        repeat(4) @(negedge clk);
        resetn = 1;
        wait(frame_done);
        @(negedge clk);
        if (clear_words != 23040 || bits != 0)
            $fatal(1, "incorrect clear frame length %0d", clear_words);
        cleared = 1;
        send_line();
        send_line();
        if (words != 320 || bits != 0)
            $fatal(1, "incorrect pixel count %0d", words);
        $display("PASS panel colours SWAP_RB=%0d white_clear=%0d pixels=%0d",
                 SWAP_RB, clear_words, words);
        $finish;
    end
    initial begin
        #10000000;
        $fatal(1, "panel colour timeout");
    end
endmodule
