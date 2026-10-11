`timescale 1ns/1ps
// Mode-0, MSB-first SPI transaction. No clocks pause while CE# is low.
// HALF_PERIOD=2 gives OSCG/4 (~12.9 MHz with DIV=6).
module spi_transaction #(
    parameter HALF_PERIOD = 2,
    parameter CS_GAP = 8
)(
    input wire clk, input wire reset,
    input wire start, input wire quad,
    input wire [55:0] tx_bits, input wire [6:0] bit_length,
    input wire miso,
    output reg cs_n, output reg sck,
    output wire [3:0] dq_out, output reg quad_drive,
    output reg busy, output reg done, output reg [23:0] rx_bits
);
    localparam IDLE=0, TRANSFER=1, HOLD=2, GAP=3;
    reg [1:0] state;
    reg [55:0] shift_tx;
    reg [6:0] remaining;
    reg [7:0] divider, wait_count;
    assign dq_out = quad_drive ? shift_tx[55:52] : {3'b000, shift_tx[55]};

    always @(posedge clk) begin
        done <= 0;
        if (reset) begin
            state <= IDLE; cs_n <= 1; sck <= 0; quad_drive <= 0;
            busy <= 0; done <= 0; rx_bits <= 0; shift_tx <= 0;
            remaining <= 0; divider <= 0; wait_count <= 0;
        end else case (state)
            IDLE: if (start) begin
                shift_tx <= tx_bits; remaining <= bit_length;
                quad_drive <= quad; rx_bits <= 0;
                cs_n <= 0; sck <= 0; busy <= 1;
                divider <= HALF_PERIOD-1; state <= TRANSFER;
            end
            TRANSFER: if (divider != 0) divider <= divider - 1'b1;
                else begin
                    divider <= HALF_PERIOD-1;
                    if (!sck) begin
                        sck <= 1;
                        if (!quad_drive) rx_bits <= {rx_bits[22:0], miso};
                    end else begin
                        sck <= 0;
                        if (remaining <= (quad_drive ? 7'd4 : 7'd1)) begin
                            wait_count <= CS_GAP-1; state <= HOLD;
                        end else begin
                            remaining <= remaining - (quad_drive ? 7'd4 : 7'd1);
                            shift_tx <= quad_drive ? {shift_tx[51:0],4'b0}
                                                   : {shift_tx[54:0],1'b0};
                        end
                    end
                end
            HOLD: if (wait_count != 0) wait_count <= wait_count-1'b1;
                else begin
                    cs_n <= 1; quad_drive <= 0; shift_tx <= 0;
                    wait_count <= CS_GAP-1; state <= GAP;
                end
            GAP: if (wait_count != 0) wait_count <= wait_count-1'b1;
                else begin busy <= 0; done <= 1; state <= IDLE; end
        endcase
    end
endmodule
