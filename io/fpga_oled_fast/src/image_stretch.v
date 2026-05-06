// image_stretch.v — convert 240x240 OLED linear pixel index to a 96x64
// image (linear) index using Bresenham-style accumulators (no division).
//
//   mode_aspect = 0  → full stretch (image fills the panel; vertical 4/15)
//   mode_aspect = 1  → aspect-preserved (image is 240x160 centered;
//                      rows 0..39 and 200..239 are letterbox = !valid_pixel)
//
// Both modes share the horizontal Bresenham (col*2/5).  iy_full uses the
// 4/15 ratio; iy_asp uses 2/5 within the active band [40, 200).
//
// Module is purely combinational on the output side: the registered state
// updates one cycle after pixel_index changes, then image_idx and
// valid_pixel are produced combinationally from that state.  Total
// latency: pixel_index change → image_idx settles 1 cycle later.
module image_stretch #(
    parameter integer IMG_W      = 96,
    parameter integer IMG_H      = 64,
    parameter integer OLED_W     = 240,
    parameter integer OLED_H     = 240,
    parameter integer ASPECT_TOP = 40,    // first active row in aspect mode
    parameter integer ASPECT_BOT = 200    // first letterbox row at bottom
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire [15:0] pixel_index,    // 0..57599
    input  wire        mode_aspect,
    output wire [12:0] image_idx,      // 0..6143
    output wire        valid_pixel     // 0 only in aspect mode's letterbox
);
    reg [7:0]  oled_col;       // 0..239
    reg [7:0]  oled_row;       // 0..239
    reg [3:0]  col_ctr;        // 0..6  (Bresenham 2/5 for ix)
    reg [3:0]  rowf_ctr;       // 0..14 (Bresenham 4/15 for iy_full)
    reg [3:0]  rowa_ctr;       // 0..6  (Bresenham 2/5 for iy_aspect)
    reg [6:0]  ix;             // 0..95
    reg [5:0]  iy_full;        // 0..63
    reg [5:0]  iy_asp;         // 0..63
    reg [15:0] pix_idx_shadow;

    wire [7:0] next_row = oled_row + 8'd1;

    always @(posedge clk) begin
        pix_idx_shadow <= pixel_index;

        if (!resetn || pixel_index == 16'd0) begin
            oled_col       <= 8'd0;
            oled_row       <= 8'd0;
            col_ctr        <= 4'd0;
            rowf_ctr       <= 4'd0;
            rowa_ctr       <= 4'd0;
            ix             <= 7'd0;
            iy_full        <= 6'd0;
            iy_asp         <= 6'd0;
        end else if (pixel_index != pix_idx_shadow) begin
            if (oled_col == 8'd239) begin
                // ---- row wrap: advance row state, reset col state ----
                oled_col <= 8'd0;
                oled_row <= next_row;
                col_ctr  <= 4'd0;
                ix       <= 7'd0;

                // iy_full Bresenham 4/15 (advances every row)
                if ({1'b0, rowf_ctr} + 4'd4 >= 5'd15) begin
                    rowf_ctr <= rowf_ctr + 4'd4 - 4'd15;
                    iy_full  <= iy_full + 6'd1;
                end else begin
                    rowf_ctr <= rowf_ctr + 4'd4;
                end

                // iy_asp Bresenham 2/5 (only in active band)
                if (next_row == ASPECT_TOP) begin
                    rowa_ctr <= 4'd0;
                    iy_asp   <= 6'd0;
                end else if (next_row > ASPECT_TOP && next_row < ASPECT_BOT) begin
                    if ({1'b0, rowa_ctr} + 4'd2 >= 4'd5) begin
                        rowa_ctr <= rowa_ctr + 4'd2 - 4'd5;
                        iy_asp   <= iy_asp + 6'd1;
                    end else begin
                        rowa_ctr <= rowa_ctr + 4'd2;
                    end
                end
                // else: letterbox (top before ASPECT_TOP, or bottom): hold
            end else begin
                // ---- col advance ----
                oled_col <= oled_col + 8'd1;
                if ({1'b0, col_ctr} + 4'd2 >= 4'd5) begin
                    col_ctr <= col_ctr + 4'd2 - 4'd5;
                    ix      <= ix + 7'd1;
                end else begin
                    col_ctr <= col_ctr + 4'd2;
                end
            end
        end
    end

    // image_idx = iy * IMG_W + ix.  IMG_W=96, so iy*96 = (iy<<6)+(iy<<5)
    wire [12:0] idx_full = {iy_full, 6'd0} + {1'b0, iy_full, 5'd0} + {6'd0, ix};
    wire [12:0] idx_asp  = {iy_asp,  6'd0} + {1'b0, iy_asp,  5'd0} + {6'd0, ix};
    wire        valid_asp = (oled_row >= ASPECT_TOP[7:0]) &&
                            (oled_row <  ASPECT_BOT[7:0]);

    assign image_idx   = mode_aspect ? idx_asp  : idx_full;
    assign valid_pixel = mode_aspect ? valid_asp : 1'b1;
endmodule
