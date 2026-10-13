module gba_flash #(parameter QSPI=0, CLOCK_CYCLES=4, RX_REGISTER=0)(
    input wire clk,clk_flash,reset, input wire request,
    input wire [24:0] address, output reg done,
    output reg [31:0] data,second_data,
    output wire flash_clk,flash_cs_n,flash_mosi,input wire flash_miso,
    input wire [2:0] quad_other, // {IO3,IO2,IO0}; IO1 is flash_miso
    output wire mosi_oe,quad_ready,quad_fault,
    output reg [31:0] misses
);
    // The core always asks for a DWORD and its address-XOR-one partner.
    // Store each pair together so both outputs share a single RAM read port.
    reg valid, start;
    reg [1:0] state;
    reg [14:0] tag;
    reg [20:0] held;
    wire busy,begin_fill,we,commit;
    wire [7:0] offset,byte_data;
    wire [22:0] unused_address;
    wire [63:0] selected_pair;
    genvar lane;
    generate for(lane=0;lane<8;lane=lane+1) begin: bytes
        reg [7:0] bank[0:31];
        always @(posedge clk)
            if(we && offset[2:0]==lane) bank[offset[7:3]]<=byte_data;
        assign selected_pair[lane*8 +: 8]=bank[held[5:1]];
    end endgenerate
    generate if(QSPI)begin: quad
        gba_qspi_backend #(.CLOCK_CYCLES(CLOCK_CYCLES),.RX_REGISTER(RX_REGISTER)) reader(
            .clk_core(clk),.clk_fast(clk_flash),.reset(reset),.start(start),
            .line_address({held,2'b00}),.dq({quad_other[2:1],flash_miso,quad_other[0]}),
            .busy(busy),.fill_begin(begin_fill),.fill_address(unused_address),
            .fill_we(we),.fill_offset(offset),.fill_data(byte_data),.fill_commit(commit),
            .flash_clk(flash_clk),.flash_cs_n(flash_cs_n),.flash_mosi(flash_mosi),
            .mosi_oe(mosi_oe),.ready(quad_ready),.fault(quad_fault));
    end else begin: serial
        assign mosi_oe=1;assign quad_ready=1;assign quad_fault=0;
    ecp5_flash_backend #(.FAST_SPI(1)) reader(
        .clk_core(clk),.clk_fast(clk_flash),.reset(reset),.start(start),
        .line_address({held,2'b00}),.busy(busy),
        .fill_begin(begin_fill),.fill_address(unused_address),
        .fill_we(we),.fill_offset(offset),.fill_data(byte_data),.fill_commit(commit),
        .flash_clk(flash_clk),.flash_cs_n(flash_cs_n),.flash_mosi(flash_mosi),.flash_miso(flash_miso));
    end endgenerate
    always @(posedge clk) begin
        done<=0;start<=0;
        if(reset) begin state<=0;valid<=0;held<=0;tag<=0;misses<=0;data<=0;second_data<=0;end
        else begin
            case(state)
                0: if(request) begin
                    held<=address[20:0];
                    state<=(valid&&tag==address[20:6]) ? 2:1;
                end
                1: if(!busy) begin start<=1;state<=3;valid<=0;misses<=misses+1'b1;end
                3: if(commit) begin valid<=1;tag<=held[20:6];state<=2;end
                2: begin
                    data<=held[0] ? selected_pair[63:32] : selected_pair[31:0];
                    second_data<=held[0] ? selected_pair[31:0] : selected_pair[63:32];
                    done<=1;state<=0;
                end
            endcase
        end
    end
endmodule
