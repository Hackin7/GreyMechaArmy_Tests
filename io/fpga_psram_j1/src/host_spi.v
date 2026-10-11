`timescale 1ns/1ps
// Slow mode-0 host SPI, oversampled by clk. Host SCK <= 1 MHz.
// Each CS falling edge snapshots the complete 8-byte reply. A command is
// exactly 5 received bytes: opcode, address[23:16], [15:8], [7:0], data.
module host_spi(
    input wire clk, input wire reset,
    input wire sck, input wire mosi, input wire cs_n,
    input wire [63:0] response,
    output wire miso,
    output reg command_valid, output reg [7:0] opcode,
    output reg [23:0] address, output reg [7:0] data
);
    (* async_reg = "true" *) reg [2:0] sck_sync, cs_sync, mosi_sync;
    reg [63:0] tx_shift;
    reg [6:0] rx_shift;
    reg [2:0] bit_count, byte_count;
    wire rising = sck_sync[2:1] == 2'b01;
    wire falling = sck_sync[2:1] == 2'b10;
    wire selected = !cs_sync[2];
    wire select_edge = cs_sync[2:1] == 2'b10;
    wire [7:0] received = {rx_shift[6:0],mosi_sync[2]};
    assign miso = tx_shift[63];
    always @(posedge clk) begin
        sck_sync <= {sck_sync[1:0],sck};
        cs_sync <= {cs_sync[1:0],cs_n};
        mosi_sync <= {mosi_sync[1:0],mosi};
        command_valid <= 0;
        if (reset) begin
            sck_sync <= 0; cs_sync <= 3'b111; mosi_sync <= 0;
            tx_shift <= 0; rx_shift <= 0; bit_count <= 0; byte_count <= 0;
            command_valid <= 0; opcode <= 0; address <= 0; data <= 0;
        end else if (!selected || select_edge) begin
            tx_shift <= response; rx_shift <= 0;
            bit_count <= 0; byte_count <= 0;
        end else begin
            if (falling) tx_shift <= {tx_shift[62:0],1'b0};
            if (rising) begin
                rx_shift <= received[6:0];
                bit_count <= bit_count + 1'b1;
                if (bit_count == 7 && byte_count < 5) begin
                    byte_count <= byte_count + 1'b1;
                    case (byte_count)
                        0: opcode <= received;
                        1: address[23:16] <= received;
                        2: address[15:8] <= received;
                        3: address[7:0] <= received;
                        4: begin data <= received; command_valid <= 1; end
                    endcase
                end
            end
        end
    end
endmodule
