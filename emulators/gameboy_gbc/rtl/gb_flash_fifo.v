// Eight-entry, 16-bit asynchronous FIFO. Distributed RAM avoids consuming
// another ECP5 block RAM. Only Gray pointers cross through synchronizers;
// the head data is stable before the synchronized write pointer exposes it.
module gb_flash_fifo (
    input wire wr_clk, input wire wr_reset,
    input wire wr_en, input wire [15:0] wr_data, output wire full,
    input wire rd_clk, input wire rd_reset,
    input wire rd_en, output wire [15:0] rd_data, output wire empty
);
    (* ram_style = "distributed" *) reg [15:0] mem [0:7];
    reg [3:0] wr_bin, wr_gray, rd_bin, rd_gray;
    (* async_reg = "true" *) reg [3:0] rd_g1, rd_g2, wr_g1, wr_g2;
    wire [3:0] wr_next = wr_bin + 4'd1;
    wire [3:0] rd_next = rd_bin + 4'd1;
    assign empty = rd_gray == wr_g2;
    assign full = wr_gray == {~rd_g2[3:2], rd_g2[1:0]};
    assign rd_data = mem[rd_bin[2:0]];
    always @(posedge wr_clk) begin
        if (wr_reset) begin
            wr_bin <= 0; wr_gray <= 0; rd_g1 <= 0; rd_g2 <= 0;
        end else begin
            rd_g1 <= rd_gray; rd_g2 <= rd_g1;
            if (wr_en && !full) begin
                mem[wr_bin[2:0]] <= wr_data;
                wr_bin <= wr_next;
                wr_gray <= (wr_next >> 1) ^ wr_next;
            end
        end
    end
    always @(posedge rd_clk) begin
        if (rd_reset) begin
            rd_bin <= 0; rd_gray <= 0; wr_g1 <= 0; wr_g2 <= 0;
        end else begin
            wr_g1 <= wr_gray; wr_g2 <= wr_g1;
            if (rd_en && !empty) begin
                rd_bin <= rd_next;
                rd_gray <= (rd_next >> 1) ^ rd_next;
            end
        end
    end
endmodule
