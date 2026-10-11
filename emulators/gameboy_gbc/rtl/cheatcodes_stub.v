// Game Genie loading is not exposed by the Army host protocol in v1.
module CODES #(
    parameter ADDR_WIDTH=16, parameter DATA_WIDTH=8, parameter MAX_CODES=32
) (
    input wire clk, input wire reset, input wire enable,
    output wire available, input wire [ADDR_WIDTH-1:0] addr_in,
    input wire [DATA_WIDTH-1:0] data_in, input wire [128:0] code,
    output wire genie_ovr, output wire [DATA_WIDTH-1:0] genie_data
);
    assign available = 1'b0;
    assign genie_ovr = 1'b0;
    assign genie_data = {DATA_WIDTH{1'b0}};
endmodule
