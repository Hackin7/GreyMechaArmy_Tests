module gb_rom_cache #(
    parameter CACHE_SET_BITS = 5 // 32 sets x 2 ways x 256 bytes = 16 KiB
) (
    input wire clk, input wire reset,
    input wire request, input wire [22:0] address,
    output reg [7:0] data, output reg ready,
    output reg miss_request, output reg [22:0] miss_address,
    input wire fill_begin, input wire [22:0] fill_address,
    input wire fill_we, input wire [7:0] fill_offset,
    input wire [7:0] fill_data, input wire fill_commit
);
    localparam SETS = 1 << CACHE_SET_BITS;
    localparam WAY_BYTES = SETS * 256;
    localparam TAG_BITS = 23 - 8 - CACHE_SET_BITS;
    reg [7:0] way0 [0:WAY_BYTES-1];
    reg [7:0] way1 [0:WAY_BYTES-1];
    reg [TAG_BITS-1:0] tag0 [0:SETS-1], tag1 [0:SETS-1];
    reg valid0 [0:SETS-1], valid1 [0:SETS-1], lru [0:SETS-1];
    reg [7:0] q0, q1;
    reg [22:0] held_address;
    reg lookup;
    reg fill_way;
    reg [CACHE_SET_BITS-1:0] fill_set;
    reg [TAG_BITS-1:0] fill_tag;
    integer i;

    wire [CACHE_SET_BITS-1:0] req_set = held_address[8+CACHE_SET_BITS-1:8];
    wire [TAG_BITS-1:0] req_tag = held_address[22:8+CACHE_SET_BITS];
    wire [CACHE_SET_BITS-1:0] incoming_set = fill_address[8+CACHE_SET_BITS-1:8];
    wire [TAG_BITS-1:0] incoming_tag = fill_address[22:8+CACHE_SET_BITS];

    always @(posedge clk) begin
        if (reset) begin
            ready <= 0; lookup <= 0; miss_request <= 0;
            held_address <= 0; fill_way <= 0; fill_set <= 0; fill_tag <= 0;
            for (i=0; i<SETS; i=i+1) begin
                valid0[i] <= 0; valid1[i] <= 0; lru[i] <= 0;
            end
        end else begin
            if (ready && (!request || address != held_address)) ready <= 0;
            if (!ready && !lookup && request && !miss_request) begin
                held_address <= address;
                q0 <= way0[address[8+CACHE_SET_BITS-1:0]];
                q1 <= way1[address[8+CACHE_SET_BITS-1:0]];
                lookup <= 1;
            end else if (lookup) begin
                lookup <= 0;
                if (valid0[req_set] && tag0[req_set] == req_tag) begin
                    data <= q0; ready <= 1; lru[req_set] <= 1;
                end else if (valid1[req_set] && tag1[req_set] == req_tag) begin
                    data <= q1; ready <= 1; lru[req_set] <= 0;
                end else begin
                    miss_request <= 1;
                    miss_address <= {held_address[22:8],8'h00};
                end
            end

            if (fill_begin) begin
                fill_set <= incoming_set; fill_tag <= incoming_tag;
                if (valid0[incoming_set] && tag0[incoming_set] == incoming_tag)
                    fill_way <= 0;
                else if (valid1[incoming_set] && tag1[incoming_set] == incoming_tag)
                    fill_way <= 1;
                else if (!valid0[incoming_set]) fill_way <= 0;
                else if (!valid1[incoming_set]) fill_way <= 1;
                else fill_way <= lru[incoming_set];
            end
            if (fill_we) begin
                if (fill_way) way1[{fill_set,fill_offset}] <= fill_data;
                else way0[{fill_set,fill_offset}] <= fill_data;
            end
            if (fill_commit) begin
                if (fill_way) begin tag1[fill_set] <= fill_tag; valid1[fill_set] <= 1; lru[fill_set] <= 0; end
                else begin tag0[fill_set] <= fill_tag; valid0[fill_set] <= 1; lru[fill_set] <= 1; end
                miss_request <= 0;
            end
        end
    end
endmodule
