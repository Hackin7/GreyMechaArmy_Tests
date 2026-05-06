// oled_stream.v — 16-bit-per-pixel SPI shifter for GC9A01 pixel data.
// ODDR-bypass version: emits a real `sclk` waveform on the output (not a
// gating signal). Each bit takes 2 sys_clk cycles: phase 0 = SCLK low
// (bit transitions on MOSI), phase 1 = SCLK high (rising edge — slave
// samples MOSI here). top.v drives the oled_scl pin directly from `sclk`,
// no ODDR primitive involved. Effective SCLK rate = sys_clk / 2.
module oled_stream (
    input  wire        clk,
    input  wire        resetn,
    input  wire        enable,
    output reg  [15:0] pixel_index,
    input  wire [15:0] pixel_data,
    output reg         sclk,
    output reg         mosi,
    output reg         cs,
    output reg         dc,
    output reg         frame_done
);
    localparam [15:0] LAST_PIX = 16'd57599;   // 240*240 - 1

    reg [15:0] shift;
    reg [3:0]  bit_cnt;
    reg        streaming;
    reg        phase;        // 0 = SCLK currently low, 1 = SCLK currently high
    reg        done_latched; // prevents spurious frame restart before sequencer drops enable

    always @(posedge clk) begin
        frame_done <= 1'b0;

        if (!resetn || !enable) begin
            pixel_index  <= 16'd0;
            shift        <= 16'd0;
            bit_cnt      <= 4'd15;
            streaming    <= 1'b0;
            phase        <= 1'b0;
            sclk         <= 1'b0;
            mosi         <= 1'b0;
            cs           <= 1'b1;
            dc           <= 1'b1;
            done_latched <= 1'b0;
        end else if (!streaming && !done_latched) begin
            // First cycle after enable rising. Load pixel 0 (already valid in
            // pixel_data via BRAM+mux from idle), set MSB on MOSI, SCLK starts
            // low, phase=0 means next cycle will raise SCLK (sample event).
            shift       <= pixel_data;
            bit_cnt     <= 4'd15;
            mosi        <= pixel_data[15];
            cs          <= 1'b0;
            dc          <= 1'b1;
            sclk        <= 1'b0;
            phase       <= 1'b0;
            streaming   <= 1'b1;
            pixel_index <= 16'd0;
        end else if (streaming) begin
            if (phase == 1'b0) begin
                // SCLK low → high (rising edge: slave samples current MOSI bit).
                sclk  <= 1'b1;
                phase <= 1'b1;
            end else begin
                // SCLK high → low. Advance to next bit on MOSI.
                sclk  <= 1'b0;
                phase <= 1'b0;

                if (bit_cnt == 4'd0) begin
                    // Last bit of this pixel just completed → load next pixel.
                    bit_cnt <= 4'd15;
                    shift   <= pixel_data;
                    mosi    <= pixel_data[15];
                    if (pixel_index == LAST_PIX) begin
                        streaming    <= 1'b0;
                        cs           <= 1'b1;
                        sclk         <= 1'b0;
                        frame_done   <= 1'b1;
                        done_latched <= 1'b1;
                    end
                end else begin
                    shift   <= {shift[14:0], 1'b0};
                    mosi    <= shift[14];
                    bit_cnt <= bit_cnt - 4'd1;
                end

                // Pre-fetch: increment pixel_index when bit_cnt==2 so BRAM (1)
                // + button mux (1) + margin (1) settles by the bit_cnt==0
                // reload three bit-periods later.
                if (bit_cnt == 4'd2 && pixel_index < LAST_PIX)
                    pixel_index <= pixel_index + 16'd1;
            end
        end
    end
endmodule
