module gb_save_cache (
    input wire clk, input wire reset,
    input wire request, input wire write_enable,
    input wire [16:0] address, input wire [7:0] write_data,
    output reg [7:0] read_data, output reg ready,
    output reg dirty_present
);
    // 2 KiB, two-way, 64-byte lines. Persistence transport is connected in
    // the next gate; this module already tracks dirtiness and mapper addresses.
    reg [7:0] way0 [0:1023], way1 [0:1023];
    reg [6:0] tag0 [0:15], tag1 [0:15];
    reg valid0 [0:15], valid1 [0:15], dirty0 [0:15], dirty1 [0:15];
    reg lru [0:15]; integer i;
    wire [3:0] set = address[9:6]; wire [6:0] tag = address[16:10];
    always @(posedge clk) begin
        ready <= 0;
        if (reset) begin
            dirty_present <= 0;
            for (i=0;i<16;i=i+1) begin
                valid0[i]<=0; valid1[i]<=0; dirty0[i]<=0; dirty1[i]<=0; lru[i]<=0;
            end
        end else if (request) begin
            if (valid0[set] && tag0[set] == tag) begin
                if (write_enable) begin way0[address[9:0]]<=write_data; dirty0[set]<=1; dirty_present<=1; end
                read_data <= way0[address[9:0]]; lru[set]<=1; ready<=1;
            end else if (valid1[set] && tag1[set] == tag) begin
                if (write_enable) begin way1[address[9:0]]<=write_data; dirty1[set]<=1; dirty_present<=1; end
                read_data <= way1[address[9:0]]; lru[set]<=0; ready<=1;
            end
        end
    end
endmodule
