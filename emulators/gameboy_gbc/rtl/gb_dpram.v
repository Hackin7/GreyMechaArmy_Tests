module dpram #(
    parameter addr_width = 8,
    parameter data_width = 8,
    parameter mem_init_file = " "
) (
    input  wire                  clock_a,
    input  wire                  clken_a,
    input  wire [addr_width-1:0] address_a,
    input  wire [data_width-1:0] data_a,
    input  wire                  wren_a,
    output reg  [data_width-1:0] q_a,
    input  wire                  clock_b,
    input  wire                  clken_b,
    input  wire [addr_width-1:0] address_b,
    input  wire [data_width-1:0] data_b,
    input  wire                  wren_b,
    output reg  [data_width-1:0] q_b
);
    reg [data_width-1:0] mem [0:(1<<addr_width)-1];

    always @(posedge clock_a) begin
        if (wren_a) mem[address_a] <= data_a;
        q_a <= wren_a ? data_a : mem[address_a];
    end
    always @(posedge clock_b) begin
        if (wren_b) mem[address_b] <= data_b;
        q_b <= wren_b ? data_b : mem[address_b];
    end
endmodule

// The upstream core uses this only for the 4 KiB CGB boot ROM: byte-wide
// core access and word-wide host update access on one clock.
module dpram_dif #(
    parameter addr_width_a = 12,
    parameter data_width_a = 8,
    parameter addr_width_b = 11,
    parameter data_width_b = 16,
    parameter mem_init_file = " "
) (
    input  wire                    clock,
    input  wire [addr_width_a-1:0] address_a,
    input  wire [data_width_a-1:0] data_a,
    input  wire                    enable_a,
    input  wire                    wren_a,
    output wire [data_width_a-1:0] q_a,
    input  wire                    cs_a,
    input  wire [addr_width_b-1:0] address_b,
    input  wire [data_width_b-1:0] data_b,
    input  wire                    enable_b,
    input  wire                    wren_b,
    output wire [data_width_b-1:0] q_b,
    input  wire                    cs_b
);
    reg [7:0] qa;
    reg [15:0] qb;

    // Boot-ROM downloading is disabled in this integration, but the complete
    // MIT-licensed MiSTer CGB boot ROM is still required to establish VRAM,
    // palettes, I/O registers, and the documented cartridge-entry CPU state.
    reg [7:0] boot_mem [0:(1<<addr_width_a)-1];
    initial begin
        if (mem_init_file != " ")
            $readmemh(mem_init_file, boot_mem);
    end

    always @(posedge clock) begin
        qa <= boot_mem[address_a];
        qb <= 16'h0000;
    end
    assign q_a = qa;
    assign q_b = qb;
endmodule
