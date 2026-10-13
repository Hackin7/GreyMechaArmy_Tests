`timescale 1ns/1ps
// One-bit mode-0 bursts: 02 writes, 03 reads or 0B with eight dummy clocks.
// tx_data is prefetched one byte ahead; no stalls while CE# is asserted.
module spi_burst #(parameter HALF_PERIOD=2, parameter CS_GAP=8,
                   parameter FAST_READ=0, parameter READ_HALF_PERIOD=HALF_PERIOD,
                   parameter READ_FALLING=0)(
    input wire clk, reset, start, write,
    input wire [23:0] address, input wire [8:0] length,
    output wire [7:0] tx_index, input wire [7:0] tx_data,
    output reg rx_valid, output reg [7:0] rx_index, rx_data,
    input wire [3:0] dq_in, output wire [3:0] dq_out,
    output wire [3:0] dq_oe,
    output reg cs_n, sck, busy, done,
    input wire sck_pad, input wire [4:0] trace_index,
    output wire [31:0] trace_word
);
    localparam IDLE=0, HEADER=1, DUMMY=2, DATA=3, HOLD=4, GAP=5;
    reg [2:0] state;
    reg [31:0] header;
    reg [5:0] bits_left;
    reg [7:0] divider, wait_count, index, tx_byte;
    reg [6:0] rx_shift;
    reg [8:0] byte_count;
    reg writing;
    localparam [7:0] WRITE_RELOAD=HALF_PERIOD[7:0]-8'd1;
    localparam [7:0] READ_RELOAD=READ_HALF_PERIOD[7:0]-8'd1;
    localparam [7:0] GAP_RELOAD=CS_GAP[7:0]-8'd1;
    wire [7:0] divider_reload=writing?WRITE_RELOAD:READ_RELOAD;
    wire unused_inputs = ^{dq_in[3:2],dq_in[0],sck_pad,trace_index};
    assign trace_word = 0;
    assign tx_index = state == DATA && writing ? index+1'b1 : index;
    assign dq_oe = 4'b0001;
    wire [2:0] tx_bit = bits_left[2:0]-3'd1;
    assign dq_out = {3'b000,state == HEADER ? header[31] :
                    (state == DATA && writing ? tx_byte[tx_bit] : 1'b0)};
    always @(posedge clk) begin
        done <= 0; rx_valid <= 0;
        if (reset) begin
            state <= IDLE; header <= 0; bits_left <= 0; divider <= 0;
            wait_count <= 0; index <= 0; tx_byte <= 0; rx_shift <= 0;
            byte_count <= 0; writing <= 0; rx_index <= 0; rx_data <= 0;
            cs_n <= 1; sck <= 0; busy <= 0; done <= 0; rx_valid <= 0;
        end else case (state)
            IDLE: if (start) begin
                header <= {write ? 8'h02 : (FAST_READ != 0 ? 8'h0b : 8'h03),address};
                bits_left <= 32; writing <= write; byte_count <= length;
                index <= 0; cs_n <= 0; sck <= 0; busy <= 1;
                divider <= write?WRITE_RELOAD:READ_RELOAD; state <= HEADER;
            end
            HEADER,DUMMY,DATA: if (divider != 0) divider <= divider-1'b1;
                else begin
                    divider <= divider_reload;
                    // Falling-edge capture gives a full SCK period for external data
                    // to settle; the new falling edge reaches the chip after capture.
                    if (state == DATA && !writing && (READ_FALLING?sck:!sck)) begin
                            rx_shift <= {rx_shift[5:0],dq_in[1]};
                            if (bits_left == 1) begin
                                rx_data <= {rx_shift,dq_in[1]};
                                rx_index <= index; rx_valid <= 1;
                            end
                    end
                    if (!sck) begin
                        sck <= 1;
                    end else begin
                        sck <= 0;
                        case (state)
                            HEADER: if (bits_left == 1) begin
                                bits_left <= 8; tx_byte <= tx_data;
                                state <= !writing && FAST_READ != 0 ? DUMMY : DATA;
                            end else begin
                                bits_left <= bits_left-1'b1;
                                header <= {header[30:0],1'b0};
                            end
                            DUMMY: if (bits_left == 1) begin bits_left <= 8; state <= DATA; end
                                   else bits_left <= bits_left-1'b1;
                            DATA: if (bits_left != 1) bits_left <= bits_left-1'b1;
                                  else if ({1'b0,index}+9'd1 == byte_count) begin
                                      wait_count <= GAP_RELOAD; state <= HOLD;
                                  end else begin
                                      index <= index+1'b1; bits_left <= 8;
                                      if (writing) tx_byte <= tx_data;
                                  end
                        endcase
                    end
                end
            HOLD: if (wait_count != 0) wait_count <= wait_count-1'b1;
                  else begin cs_n <= 1; wait_count <= GAP_RELOAD; state <= GAP; end
            GAP: if (wait_count != 0) wait_count <= wait_count-1'b1;
                 else begin busy <= 0; done <= 1; state <= IDLE; end
        endcase
    end
endmodule
