// Direct-clocked GC9A01 line streamer.  This uses the same SCLK/MOSI timing
// as the panel-proven oled_stream used by the Arduboy port: MOSI changes while
// SCLK is low and the panel samples on the following rising edge.  Unlike the
// old byte-SPI implementation, it never relies on simple_spi_master at its
// unreliable divider-zero setting.
module gc9a01_line_stream #(
    parameter SWAP_RB = 1
) (
    input wire clk, input wire resetn, input wire enable,
    input wire line_ready, input wire line_bank, input wire [7:0] line_number,
    output reg line_done, output reg [7:0] rd_addr, output reg rd_bank,
    input wire [15:0] rd_data, output reg frame_done,
    output reg sclk, output reg mosi, output reg dc, output reg cs_n
);
    localparam WAIT_LINE = 2'd0, PREFETCH = 2'd1, STREAM = 2'd2,
               WAIT_ACK = 2'd3;
    reg [1:0] state;
    reg [15:0] shift;
    reg [3:0] bit_count;
    reg [7:0] pixel_count;
    reg phase;
    reg prefetch_wait;
    reg clearing;
    reg [7:0] clear_line;
    // Keep core/line-buffer pixels in logical RGB565. Match the channel
    // correction used by the panel-proven Arduboy driver at serialization.
    wire [15:0] panel_data = SWAP_RB
        ? {rd_data[4:0], rd_data[10:5], rd_data[15:11]} : rd_data;

    always @(posedge clk) begin
        line_done  <= 1'b0;
        frame_done <= 1'b0;
        if (!resetn) begin
            state     <= WAIT_LINE;
            rd_addr   <= 0;
            rd_bank   <= 0;
            shift     <= 0;
            bit_count <= 4'd15;
            pixel_count <= 0;
            phase     <= 0;
            prefetch_wait <= 0;
            clearing  <= 1'b1;
            clear_line <= 0;
            sclk      <= 0;
            mosi      <= 0;
            dc        <= 1;
            cs_n      <= 1;
        end else if (!enable) begin
            // A frame rearm temporarily gives the panel pins back to the
            // initializer.  Reset the serializer, but preserve clearing so
            // the all-white frame is sent only once after global reset.
            state     <= WAIT_LINE;
            rd_addr   <= 0;
            rd_bank   <= 0;
            shift     <= 0;
            bit_count <= 4'd15;
            pixel_count <= 0;
            phase     <= 0;
            prefetch_wait <= 0;
            sclk      <= 0;
            mosi      <= 0;
            dc        <= 1;
            cs_n      <= 1;
        end else begin
            case (state)
                WAIT_LINE: begin
                    sclk <= 1'b0;
                    dc   <= 1'b1;
                    // Always send a white frame first.  This removes any
                    // CircuitPython/menu image before the Game Boy core is
                    // allowed to supply its first scanline.
                    if (clearing || line_ready) begin
                        rd_addr <= 0;
                        rd_bank <= line_bank;
                        // The first line owns CS; later lines retain it so
                        // RAMWR remains one continuous pixel transaction.
                        cs_n <= 1'b0;
                        prefetch_wait <= 1'b1;
                        state <= PREFETCH;
                    end
                end
                PREFETCH: begin
                    // gb_line_capture has a synchronous panel-side read.
                    // rd_addr/bank were assigned on the previous edge. The
                    // RAM registers that address now; latch on the next edge.
                    if (prefetch_wait) begin
                        prefetch_wait <= 1'b0;
                    end else begin
                        shift     <= clearing ? 16'hFFFF : panel_data;
                        mosi      <= clearing ? 1'b1 : panel_data[15];
                        bit_count <= 4'd15;
                        pixel_count <= 0;
                        phase     <= 1'b0;
                        sclk      <= 1'b0;
                        state     <= STREAM;
                    end
                end
                STREAM: begin
                    if (!phase) begin
                        sclk  <= 1'b1;
                        phase <= 1'b1;
                    end else begin
                        sclk  <= 1'b0;
                        phase <= 1'b0;
                        if (bit_count == 0) begin
                            // rd_addr advances early to prefetch the next
                            // synchronous-BRAM word, so count transmitted
                            // pixels separately or every row stops at 159.
                            if (pixel_count == 8'd159) begin
                                if (clearing) begin
                                    if (clear_line == 8'd143) begin
                                        clearing <= 1'b0;
                                        clear_line <= 0;
                                        frame_done <= 1'b1;
                                        cs_n <= 1'b1;
                                    end else begin
                                        clear_line <= clear_line + 1'b1;
                                    end
                                end else begin
                                    line_done <= 1'b1;
                                    if (line_number == 8'd143) begin
                                    frame_done <= 1'b1;
                                    cs_n <= 1'b1;
                                    end
                                end
                                state <= clearing ? WAIT_LINE : WAIT_ACK;
                            end else begin
                                pixel_count <= pixel_count + 1'b1;
                                bit_count <= 4'd15;
                                shift <= clearing ? 16'hFFFF : panel_data;
                                mosi <= clearing ? 1'b1 : panel_data[15];
                            end
                        end else begin
                            shift <= {shift[14:0], 1'b0};
                            mosi <= shift[14];
                            bit_count <= bit_count - 1'b1;
                        end
                        // Request the next line-buffer pixel three bit times
                        // before it is consumed, matching the proven streamer.
                        if (bit_count == 4'd2 && rd_addr != 8'd159)
                            rd_addr <= rd_addr + 1'b1;
                    end
                end
                WAIT_ACK: begin
                    // Do not consume the still-asserted ready level twice.
                    sclk <= 1'b0;
                    if (!line_ready)
                        state <= WAIT_LINE;
                end
            endcase
        end
    end
endmodule
