`timescale 1ns/1ps
// APS6404L SPI byte controller. Requests accepted only when ready && !busy.
// Startup: >=150 us wait, QPI exit, 66/99 reset, then 9F + 24 address bits
// + 24 ID bits. Read-ID always follows reset as required by the datasheet.
module psram_spi #(parameter POWERUP_CYCLES=20000, parameter ENABLE_QPI=0,
                   parameter INIT_HALF_PERIOD=2)(
    input wire clk, input wire reset,
    input wire request, input wire [1:0] operation,
    input wire [23:0] address, input wire [7:0] write_data,
    output wire busy, output reg ready, output reg done, output reg qpi_mode,
    output reg [7:0] read_data, output reg [23:0] device_id,
    output wire cs_n, output wire sck,
    input wire [3:0] dq_in, output wire [3:0] dq_out,
    output wire [3:0] dq_oe
);
    // operation 0=read, 1=write, 2=reset/read-ID.
    localparam POWER=0, QSTART=1, QWAIT=2, ESTART=3, EWAIT=4,
               RSTART=5, RWAIT=6, ISTART=7, IWAIT=8, IDLE=9, OWAIT=10,
               ENSTART=11, ENWAIT=12;
    reg [3:0] state;
    reg [31:0] power_count;
    reg spi_start, spi_quad;
    reg [55:0] spi_tx;
    reg [6:0] spi_length;
    wire unused_spi_busy, spi_done, spi_quad_drive;
    wire unused_dq = ^{dq_in[3:2],dq_in[0]};
    wire [23:0] spi_rx;
    wire [3:0] spi_dq_out;
    assign busy = (state != IDLE);
    assign dq_out = (state == POWER) ? 4'b0 : spi_dq_out;
    assign dq_oe = (state == POWER || spi_quad_drive) ? 4'b1111 : 4'b0001;
    spi_transaction #(.HALF_PERIOD(INIT_HALF_PERIOD)) spi(.clk(clk), .reset(reset), .start(spi_start),
        .quad(spi_quad), .tx_bits(spi_tx), .bit_length(spi_length),
        .miso(dq_in[1]), .cs_n(cs_n), .sck(sck), .dq_out(spi_dq_out),
        .quad_drive(spi_quad_drive), .busy(unused_spi_busy), .done(spi_done),
        .rx_bits(spi_rx));

    always @(posedge clk) begin
        spi_start <= 0; done <= 0;
        if (reset) begin
            state <= POWER; power_count <= 0; ready <= 0; done <= 0;
            spi_start <= 0; spi_quad <= 0; spi_tx <= 0; spi_length <= 0;
            read_data <= 0; device_id <= 0; qpi_mode <= 0;
        end else case (state)
            POWER: if (power_count == POWERUP_CYCLES-1) state <= QSTART;
                   else power_count <= power_count + 1'b1;
            QSTART: begin
                spi_tx <= {8'hf5,48'b0}; spi_length <= 8; spi_quad <= 1;
                spi_start <= 1; state <= QWAIT;
            end
            QWAIT: if (spi_done) state <= ESTART;
            ESTART: begin
                spi_tx <= {8'h66,48'b0}; spi_length <= 8; spi_quad <= 0;
                spi_start <= 1; state <= EWAIT;
            end
            EWAIT: if (spi_done) state <= RSTART;
            RSTART: begin
                spi_tx <= {8'h99,48'b0}; spi_length <= 8;
                spi_start <= 1; state <= RWAIT;
            end
            RWAIT: if (spi_done) state <= ISTART;
            ISTART: begin
                spi_tx <= {8'h9f,48'b0}; spi_length <= 56;
                spi_start <= 1; state <= IWAIT;
            end
            IWAIT: if (spi_done) begin
                device_id <= spi_rx[23:0]; read_data <= spi_rx[7:0];
                if (ENABLE_QPI != 0) state <= ENSTART;
                else begin ready <= 1; done <= 1; state <= IDLE; end
            end
            ENSTART: begin
                spi_tx <= {8'h35,48'b0}; spi_length <= 8; spi_quad <= 0;
                spi_start <= 1; state <= ENWAIT;
            end
            ENWAIT: if (spi_done) begin
                ready <= 1; done <= 1; qpi_mode <= 1; state <= IDLE;
            end
            IDLE: if (request) begin
                if (operation == 2) begin ready <= 0; qpi_mode <= 0; state <= QSTART; end
                else begin
                    spi_tx <= {(operation == 1 ? 8'h02 : 8'h03),address,
                               (operation == 1 ? write_data : 8'b0),16'b0};
                    spi_length <= 40; spi_quad <= 0; spi_start <= 1;
                    state <= OWAIT;
                end
            end
            OWAIT: if (spi_done) begin
                read_data <= spi_rx[7:0]; done <= 1; state <= IDLE;
            end
        endcase
    end
endmodule
