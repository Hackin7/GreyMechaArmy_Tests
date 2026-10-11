module gb_host_bridge (
    input wire clk, input wire reset,
    input wire [7:0] rx_data, input wire rx_valid,
    output reg [7:0] tx_data, output reg tx_valid, input wire tx_ready,
    input wire cache_miss, input wire [22:0] cache_miss_address,
    input wire core_running, input wire lcd_on, input wire lcd_clock,
    input wire [15:0] pixel_count, input wire [15:0] debug_pc,
    output reg rom_we, output reg [22:0] rom_addr, output reg [7:0] rom_data,
    output reg fill_begin, output reg fill_we, output reg [7:0] fill_offset,
    output reg [7:0] fill_data, output reg fill_commit,
    output reg [22:0] fill_address,
    output reg core_reset_pulse, output reg core_run, output reg gbc_mode,
    output reg irq, output reg [7:0] last_sequence,
    output reg [3:0] error_code
);
    localparam MAGIC=8'h47, VERSION=8'h01;
    localparam OP_RESET=8'h01, OP_CONFIG=8'h02, OP_RUN=8'h03,
               OP_ROM_WRITE=8'h10, OP_CACHE_FILL=8'h11, OP_STATUS=8'h20;
    localparam WAIT_MAGIC=0, GET_VERSION=1, GET_OPCODE=2, GET_SEQUENCE=3,
               GET_A0=4, GET_A1=5, GET_A2=6, GET_A3=7,
               GET_L0=8, GET_L1=9, GET_PAYLOAD=10,
               GET_CRC0=11, GET_CRC1=12, COMMIT=13;
    reg [3:0] state;
    reg [7:0] opcode, packet_sequence, crc_low;
    reg [31:0] address;
    reg [8:0] length, count, commit_count;
    reg [15:0] crc;
    reg [7:0] payload [0:255];
    reg [2:0] response_left;
    reg [1:0] response_index;

    function [15:0] crc_byte;
        input [15:0] old_crc; input [7:0] value;
        integer i; reg [15:0] c;
        begin
            c = old_crc ^ {value,8'h00};
            for (i=0; i<8; i=i+1)
                c = c[15] ? {c[14:0],1'b0} ^ 16'h1021 : {c[14:0],1'b0};
            crc_byte = c;
        end
    endfunction

    always @(posedge clk) begin
        rom_we <= 0; fill_begin <= 0; fill_we <= 0; fill_commit <= 0;
        core_reset_pulse <= 0;
        if (reset) begin
            state <= WAIT_MAGIC; crc <= 16'hffff; count <= 0;
            commit_count <= 0; gbc_mode <= 1; core_run <= 0; irq <= 0;
            last_sequence <= 0; error_code <= 0;
            response_left <= 0; response_index <= 0;
            tx_valid <= 0;
        end else begin
            if (tx_valid && tx_ready) begin
                tx_valid <= 0;
                response_left <= response_left - 1'b1;
                response_index <= response_index + 1'b1;
            end
            if (!tx_valid && response_left != 0) begin
                case (response_index)
                    0: tx_data <= {cache_miss,core_running,lcd_on,lcd_clock,error_code};
                    1: tx_data <= cache_miss_address[7:0];
                    2: tx_data <= cache_miss_address[15:8];
                    default: tx_data <= {1'b0,cache_miss_address[22:16]};
                endcase
                tx_valid <= 1;
            end
            if (state == COMMIT) begin
                if (opcode == OP_ROM_WRITE && commit_count < length) begin
                    rom_we <= 1; rom_addr <= address[22:0] + commit_count;
                    rom_data <= payload[commit_count[7:0]];
                    commit_count <= commit_count + 1'b1;
                end else if (opcode == OP_CACHE_FILL && commit_count < length) begin
                    fill_we <= 1; fill_offset <= commit_count[7:0];
                    fill_data <= payload[commit_count[7:0]];
                    commit_count <= commit_count + 1'b1;
                end else begin
                    if (opcode == OP_CACHE_FILL) fill_commit <= 1;
                    if (opcode == OP_RESET) begin core_reset_pulse <= 1; core_run <= 0; end
                    if (opcode == OP_RUN) core_run <= 1;
                    if (opcode == OP_CONFIG && length != 0) gbc_mode <= payload[0][0];
                    last_sequence <= packet_sequence;
                    if (opcode == OP_STATUS) begin
                        response_left <= 4; response_index <= 0;
                    end
                    state <= WAIT_MAGIC;
                end
            end else if (rx_valid) begin
                case (state)
                    WAIT_MAGIC: if (rx_data == MAGIC) begin
                        crc <= crc_byte(16'hffff, rx_data); state <= GET_VERSION;
                        irq <= 0; error_code <= 0;
                    end
                    GET_VERSION: if (rx_data == VERSION) begin
                        crc <= crc_byte(crc,rx_data); state <= GET_OPCODE;
                    end else begin error_code <= 1; state <= WAIT_MAGIC; end
                    GET_OPCODE: begin opcode <= rx_data; crc <= crc_byte(crc,rx_data); state <= GET_SEQUENCE; end
                    GET_SEQUENCE: begin packet_sequence <= rx_data; crc <= crc_byte(crc,rx_data); state <= GET_A0; end
                    GET_A0: begin address[7:0] <= rx_data; crc <= crc_byte(crc,rx_data); state <= GET_A1; end
                    GET_A1: begin address[15:8] <= rx_data; crc <= crc_byte(crc,rx_data); state <= GET_A2; end
                    GET_A2: begin address[23:16] <= rx_data; crc <= crc_byte(crc,rx_data); state <= GET_A3; end
                    GET_A3: begin address[31:24] <= rx_data; crc <= crc_byte(crc,rx_data); state <= GET_L0; end
                    GET_L0: begin length[7:0] <= rx_data; crc <= crc_byte(crc,rx_data); state <= GET_L1; end
                    GET_L1: begin
                        crc <= crc_byte(crc,rx_data); count <= 0;
                        if (rx_data > 1 || (rx_data == 1 && length[7:0] != 0)) begin
                            error_code <= 2; state <= WAIT_MAGIC;
                        end else begin
                            length[8] <= rx_data[0];
                            state <= (rx_data == 0 && length[7:0] == 0)
                                   ? GET_CRC0 : GET_PAYLOAD;
                        end
                    end
                    GET_PAYLOAD: begin
                        payload[count[7:0]] <= rx_data; crc <= crc_byte(crc,rx_data);
                        count <= count + 1'b1;
                        if (count + 1'b1 == length) state <= GET_CRC0;
                    end
                    GET_CRC0: begin crc_low <= rx_data; state <= GET_CRC1; end
                    GET_CRC1: begin
                        if ({rx_data,crc_low} != crc) begin error_code <= 3; irq <= 1; state <= WAIT_MAGIC; end
                        else begin
                            commit_count <= 0; fill_address <= address[22:0];
                            if (opcode == OP_CACHE_FILL) fill_begin <= 1;
                            state <= COMMIT;
                        end
                    end
                    default: state <= WAIT_MAGIC;
                endcase
            end
        end
    end
endmodule
