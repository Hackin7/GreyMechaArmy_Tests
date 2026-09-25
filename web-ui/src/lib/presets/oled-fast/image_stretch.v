// image_stretch.v — convert 240x240 OLED linear pixel index to a 96x64
// image (linear) index using Bresenham-style accumulators (no division).
//
//   mode = 2'b00 (FULL)   → image fills entire panel; vertical Bresenham 4/15
//   mode = 2'b01 (ASPECT) → image is 240x160 centered; rows 0..39 and
//                           200..239 are letterbox (valid_pixel = 0)
//   mode = 2'b10 (CIRCLE) → image at 2x scale (192x128) centered; fits
//                           entirely inside the inscribed circle of the
//                           GC9A01's circular display (worst-case corner
//                           radius √(96²+64²) ≈ 115.4 < 120). Letterbox
//                           outside the 192x128 region is invalid.
//   mode = 2'b11          → reserved (treated as FULL)
//
// All three modes share the same oled_col/oled_row counters and the
// horizontal Bresenham (col_ctr/ix). FULL adds a 4/15 vertical Bresenham
// (rowf_ctr/iy_full); ASPECT adds a 2/5 vertical Bresenham over the active
// band [40,200) (rowa_ctr/iy_asp); CIRCLE is purely combinational from
// oled_col/oled_row (just offset+shift). All accumulators run in parallel,
// the output mux selects the active mode.
//
// Latency: pixel_index change → image_idx settles 1 cycle later (one
// pipeline register on the accumulator state).
module image_stretch #(
    parameter integer IMG_W      = 96,
    parameter integer IMG_H      = 64,
    parameter integer OLED_W     = 240,
    parameter integer OLED_H     = 240,
    parameter integer ASPECT_TOP = 40,    // first active row in aspect mode
    parameter integer ASPECT_BOT = 200,   // first letterbox row at bottom
    parameter integer CIRCLE_LEFT = 24,   // first active col in circle mode (192 wide centered)
    parameter integer CIRCLE_RIGHT = 216, // first letterbox col at right
    parameter integer CIRCLE_TOP   = 56,  // first active row in circle mode (128 high centered)
    parameter integer CIRCLE_BOT   = 184  // first letterbox row at bottom
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire [15:0] pixel_index,    // 0..57599
    input  wire [1:0]  mode,           // 00=FULL, 01=ASPECT, 10=CIRCLE
    output wire [12:0] image_idx,      // 0..6143
    output wire        valid_pixel     // 0 in letterbox regions
);
    localparam [1:0] MODE_FULL   = 2'b00;
    localparam [1:0] MODE_ASPECT = 2'b01;
    localparam [1:0] MODE_CIRCLE = 2'b10;

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
                if (next_row == ASPECT_TOP[7:0]) begin
                    rowa_ctr <= 4'd0;
                    iy_asp   <= 6'd0;
                end else if (next_row > ASPECT_TOP[7:0] && next_row < ASPECT_BOT[7:0]) begin
                    if ({1'b0, rowa_ctr} + 4'd2 >= 4'd5) begin
                        rowa_ctr <= rowa_ctr + 4'd2 - 4'd5;
                        iy_asp   <= iy_asp + 6'd1;
                    end else begin
                        rowa_ctr <= rowa_ctr + 4'd2;
                    end
                end
                // else (top letterbox before ASPECT_TOP, or bottom letterbox): hold
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

    // CIRCLE mode: 2x scale, image displayed at 192x128 centered.
    // ix_circ = (col - CIRCLE_LEFT) >> 1 when col in active band
    // iy_circ = (row - CIRCLE_TOP)  >> 1 when row in active band
    wire [7:0] col_minus = oled_col - CIRCLE_LEFT[7:0];
    wire [7:0] row_minus = oled_row - CIRCLE_TOP[7:0];
    wire [6:0] ix_circ   = col_minus[7:1];
    wire [5:0] iy_circ   = row_minus[6:1];
    wire [12:0] idx_circ = {iy_circ, 6'd0} + {1'b0, iy_circ, 5'd0} + {6'd0, ix_circ};
    wire valid_circle    = (oled_col >= CIRCLE_LEFT[7:0]) &&
                           (oled_col <  CIRCLE_RIGHT[7:0]) &&
                           (oled_row >= CIRCLE_TOP[7:0]) &&
                           (oled_row <  CIRCLE_BOT[7:0]);

    wire valid_aspect    = (oled_row >= ASPECT_TOP[7:0]) &&
                           (oled_row <  ASPECT_BOT[7:0]);

    assign image_idx   = (mode == MODE_CIRCLE) ? idx_circ :
                         (mode == MODE_ASPECT) ? idx_asp  :
                                                 idx_full;
    assign valid_pixel = (mode == MODE_CIRCLE) ? valid_circle :
                         (mode == MODE_ASPECT) ? valid_aspect :
                                                 1'b1;
endmodule
