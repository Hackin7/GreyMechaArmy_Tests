`timescale 1ns/1ps
// QPI SDR: 02 writes, 0B reads (four dummy clocks), 1..128 bytes.
// Streaming bytes must be available without backpressure while CE# is low.
module qpi_burst #(parameter HALF_PERIOD=2, parameter CS_GAP=8, parameter TRACE=0)(
    input wire clk, input wire reset, input wire start, input wire write,
    input wire [23:0] address, input wire [8:0] length,
    output wire [7:0] tx_index, input wire [7:0] tx_data,
    output reg rx_valid, output reg [7:0] rx_index, output reg [7:0] rx_data,
    input wire [3:0] dq_in, output wire [3:0] dq_out, output reg [3:0] dq_oe,
    output reg cs_n, output reg sck, output reg busy, output reg done,
    input wire sck_pad, input wire [4:0] trace_index, output wire [31:0] trace_word
);
    localparam IDLE=0, HEADER=1, DUMMY=2, DATA=3, HOLD=4, GAP=5;
    reg [2:0] state;
    reg [31:0] header;
    reg [3:0] header_left, dummy_left;
    reg [7:0] divider, wait_count, index;
    reg [8:0] byte_count;
    reg writing, low_nibble;
    reg [3:0] high_data;
    reg [7:0] tx_byte;
    assign tx_index = state == DATA && writing ? index+1'b1 : index;
    generate if (TRACE != 0) begin: scope
        reg [1023:0] history;
        always @(posedge clk) begin
            if (reset) history <= 0;
            else if (busy) history <= {history[1007:0],state,low_nibble,sck_pad,sck,dq_oe[0],rx_valid,dq_in,rx_data[3:0]};
        end
        assign trace_word = history[{trace_index,5'b0} +: 32];
    end else begin: no_scope
        wire unused_trace_inputs = ^{sck_pad,trace_index};
        assign trace_word = 0;
    end endgenerate
    assign dq_out = state == HEADER ? header[31:28] :
                    (state == DATA && writing ?
                    (low_nibble ? tx_byte[3:0] : tx_byte[7:4]) : 4'b0);
    always @(posedge clk) begin
        done <= 0; rx_valid <= 0;
        if (reset) begin
            state <= IDLE; header <= 0; header_left <= 0; dummy_left <= 0;
            divider <= 0; wait_count <= 0; index <= 0; byte_count <= 0;
            writing <= 0; low_nibble <= 0; high_data <= 0; tx_byte <= 0;
            rx_index <= 0; rx_data <= 0; dq_oe <= 0;
            cs_n <= 1; sck <= 0; busy <= 0; done <= 0; rx_valid <= 0;
        end else case (state)
            IDLE: if (start) begin
                header <= {write ? 8'h02 : 8'h0b,address};
                dq_oe <= 4'hf;
                writing <= write; byte_count <= length; index <= 0;
                header_left <= 8; cs_n <= 0; sck <= 0; busy <= 1;
                divider <= HALF_PERIOD-1; state <= HEADER;
            end
            HEADER, DUMMY, DATA: if (divider != 0) divider <= divider-1'b1;
                else begin
                    divider <= HALF_PERIOD-1;
                    if (!sck) begin
                        sck <= 1;
                        if (state == DATA && !writing) begin
                            if (!low_nibble) high_data <= dq_in;
                            else begin
                                rx_data <= {high_data,dq_in}; rx_index <= index; rx_valid <= 1;
                            end
                        end
                    end else begin
                        sck <= 0;
                        case (state)
                            HEADER: if (header_left == 1) begin
                                low_nibble <= 0;
                                if (writing) begin tx_byte <= tx_data; state <= DATA; end
                                else begin dq_oe <= 0; dummy_left <= 4; state <= DUMMY; end
                            end else begin
                                header <= {header[27:0],4'b0};
                                header_left <= header_left-1'b1;
                            end
                            DUMMY: if (dummy_left == 1) begin
                                       low_nibble <= 0; state <= DATA;
                                   end
                                   else dummy_left <= dummy_left-1'b1;
                            DATA: begin
                              if (!low_nibble) begin
                                low_nibble <= 1;
                            end else if ({1'b0,index}+9'd1 == byte_count) begin
                                wait_count <= CS_GAP-1; state <= HOLD;
                            end else begin
                                index <= index+1'b1; low_nibble <= 0;
                                if (writing) tx_byte <= tx_data;
                            end
                            end
                        endcase
                    end
                end
            HOLD: if (wait_count != 0) wait_count <= wait_count-1'b1;
                else begin
                    cs_n <= 1; dq_oe <= 0;
                    wait_count <= CS_GAP-1; state <= GAP;
                end
            GAP: if (wait_count != 0) wait_count <= wait_count-1'b1;
                 else begin busy <= 0; done <= 1; state <= IDLE; end
        endcase
    end
endmodule
