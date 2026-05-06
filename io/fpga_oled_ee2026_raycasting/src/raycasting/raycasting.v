`timescale 1ns / 1ps

// raycasting.v — adapted from io/raycasting/raycasting.v for the greybadge
// dual-clock build. Changes from the original:
//   1. sin/cos LUTs shrunk from 65536 to 4096 entries (every 16th sampled).
//      All array reads index `[X >> 4]` to compensate. Saves ~16 EBRs per LUT
//      so it fits the ECP5-25K BRAM budget.
//   2. clk_counter thresholds scaled by 1/8 (100 MHz -> 12.5 MHz slow clock)
//      so wall-time timing of bills/movement matches the original.
//   3. .mem file paths point into src/raycasting/ relative to project root.
//   4. All non-power-of-2 `/` divisions replaced with case-statement LUT
//      functions. The original synthesised iterative-subtraction divider
//      trees that blew the LUT count to ~180% on ECP5-25K. The values are
//      bounded (distance 0..50, colour_factor 1..~13) so small LUTs cover
//      the active range; out-of-range inputs return safe defaults.
//   5. oled_xpos / oled_ypos taken as inputs instead of computed via
//      `% 96` and `/ 96` — top.v maintains them as counters in lockstep
//      with scan_idx, which is free.

module raycasting # (
    parameter STR_LEN = 15
)(
    // Control
    input reset, input clk,
    // LEDs, Switches, Buttons
    input btnC, btnU, btnL, btnR, btnD,
    // 7 Segment Display
    output [6:0] seg, output dp, output [3:0] an,
    // OLED
    input [12:0] oled_pixel_index, output [15:0] oled_pixel_data,
    input [7:0] oled_xpos, input [7:0] oled_ypos,
    // OLED Text Module
    output [8*STR_LEN*7-1:0] text_lines, output [15:0] text_colour,

    // Mouse - NOT NEEDED
    input [11:0] mouse_xpos,  mouse_ypos, input [3:0] mouse_zpos,
    input mouse_left_click, mouse_middle_click, mouse_right_click, mouse_new_event
);

    // ---- LUT replacements for the original combinational divisions ----
    // 64 / d  for d in 0..63 (distance is bounded to <=50 in practice).
    function automatic [7:0] div64(input [7:0] d);
        case (d)
            8'd0,  8'd1:                    div64 = 8'd64;
            8'd2:                           div64 = 8'd32;
            8'd3:                           div64 = 8'd21;
            8'd4:                           div64 = 8'd16;
            8'd5:                           div64 = 8'd12;
            8'd6:                           div64 = 8'd10;
            8'd7:                           div64 = 8'd9;
            8'd8:                           div64 = 8'd8;
            8'd9:                           div64 = 8'd7;
            8'd10:                          div64 = 8'd6;
            8'd11, 8'd12:                   div64 = 8'd5;
            8'd13, 8'd14, 8'd15, 8'd16:     div64 = 8'd4;
            8'd17, 8'd18, 8'd19, 8'd20, 8'd21: div64 = 8'd3;
            8'd22, 8'd23, 8'd24, 8'd25, 8'd26, 8'd27, 8'd28, 8'd29, 8'd30, 8'd31, 8'd32: div64 = 8'd2;
            default:                        div64 = 8'd1;
        endcase
    endfunction

    // 31 / cf  (5-bit / colour_factor). colour_factor in 1..15 covers it.
    function automatic [4:0] div31(input [7:0] cf);
        case (cf)
            8'd0,  8'd1: div31 = 5'd31;
            8'd2:        div31 = 5'd15;
            8'd3:        div31 = 5'd10;
            8'd4:        div31 = 5'd7;
            8'd5:        div31 = 5'd6;
            8'd6:        div31 = 5'd5;
            8'd7:        div31 = 5'd4;
            8'd8, 8'd9, 8'd10: div31 = 5'd3;
            8'd11, 8'd12, 8'd13, 8'd14, 8'd15: div31 = 5'd2;
            default:     div31 = 5'd1;
        endcase
    endfunction

    // 63 / cf
    function automatic [5:0] div63(input [7:0] cf);
        case (cf)
            8'd0,  8'd1: div63 = 6'd63;
            8'd2:        div63 = 6'd31;
            8'd3:        div63 = 6'd21;
            8'd4:        div63 = 6'd15;
            8'd5:        div63 = 6'd12;
            8'd6:        div63 = 6'd10;
            8'd7:        div63 = 6'd9;
            8'd8, 8'd9:  div63 = 6'd7;
            8'd10:       div63 = 6'd6;
            8'd11, 8'd12: div63 = 6'd5;
            8'd13, 8'd14, 8'd15: div63 = 6'd4;
            default:     div63 = 6'd3;
        endcase
    endfunction
    // 7-seg / text outputs are not used on the greybadge.
    assign seg         = 7'b1111111;
    assign dp          = 1'b1;
    assign an          = 4'b1111;
    assign text_lines  = {(8*STR_LEN*7){1'b0}};
    assign text_colour = 16'h0000;

    //// Setup ///////////////////////////////////////////////////////////////////////////////////////////////////////
    //// Clocks /////////////////////////////////////////////
    // Scaled 1/8 from 100 MHz to fit our 12.5 MHz slow clock.
    wire clk_100hz;
    clk_counter #(250_000, 250_000, 32) clk100 (clk, clk_100hz);

    wire clk_10hz;
    clk_counter #(1_250_000, 1_250_000, 32) clk10 (clk, clk_10hz);
    //// 3.A OLED Setup //////////////////////////////////////
    // oled_xpos / oled_ypos now come in via ports (top.v counter), no
    // mod/div on oled_pixel_index needed.

    /* Bills overlay removed for ECP5-25K — the 5 inlined display_bill task
     * calls each forced an independent combinational read of money_bill_img,
     * which yosys couldn't share across read ports. Costed too many LUTs.
     */
    /// Raycasting ////////////////////////////////////////////////


    constants constant();
    parameter BW_INT=8;
    parameter BW_DEC=8;
    parameter BW = BW_INT + BW_DEC;
    parameter FOV = 60;



    // Shrunk to 4096 entries (was 65536). Index reads use `[idx >> 4]` so
    // the angular relationship to the precomputed LUTs is preserved.
    reg signed [15:0] sin_array [4095:0];
    reg signed [15:0] cos_array [4095:0];
    initial begin
        $readmemh("src/raycasting/sin.mem", sin_array);
        $readmemh("src/raycasting/cos.mem", cos_array);
    end


    function [BW:0] min(input [BW:0] a, input [BW:0] b);
    begin
        min = a < b ? a : b;
    end
    endfunction

    function [BW-1:0] abs_cos(input [BW-1:0] a);
    begin
        if (cos_array[a >> 4] < 0) begin
            abs_cos = -cos_array[a >> 4];
        end else begin
            abs_cos = cos_array[a >> 4];
        end
    end
    endfunction
    /* -----------------------------------------------------*/

    parameter world_width = 8;
    reg [63:0] world_map =
    {
        8'b11111111,
        8'b10000001,
        8'b10000001,
        8'b10000001,
        8'b10000001,
        8'b10000001,
        8'b10000001,
        8'b11111111
    };

    reg [12:0] prev_pixel_index = 0;
    reg [BW-1:0] distance=9;

    // Player Variables
    reg [BW-1+8:0] x_precise = (2 << BW_DEC) << 8;
    reg [BW-1+8:0] y_precise = (2 << BW_DEC) << 8;
    wire [BW-1:0] x = x_precise[BW-1+8:8];
    wire [BW-1:0] y = y_precise[BW-1+8:8];
    reg [BW-1+1:0] angle = 90 << BW_DEC; // add 1 bit to range 360
    wire [BW-1:0] angle_processed = (
        angle + (48 << BW_DEC) > (360 << BW_DEC) ? (angle+(48 << BW_DEC)) -  (360 << BW_DEC):
        angle + (48 << BW_DEC) > (180 << BW_DEC) ? (360 << BW_DEC) - (angle+(48 << BW_DEC)) :
        (angle+(48 << BW_DEC))
    );

    // Calculations
    reg [7:0] raycast_step = 0;
    //wire [BW-1:0] raycast_angle = angle + oled_xpos;
    wire signed [BW-1+1:0] raycast_angle = (
        angle + (oled_xpos << BW_DEC) > (360 << BW_DEC)
            ? angle + (oled_xpos << BW_DEC) - (360 << BW_DEC)
        : angle + (oled_xpos << BW_DEC) > (180 << BW_DEC)
            ? (360 << BW_DEC) - (angle + (oled_xpos << BW_DEC))
        : angle + (oled_xpos << BW_DEC)
    );

    // Registered (synchronous) reads of sin/cos so yosys infers DP16KD with
    // its output register engaged — async reads on a 4096-entry table fall
    // back to LUT logic and explode the cell count by ~8000 LUT4s.
    // dx/dy lag raycast_angle by 1 cycle; raycast_step still increments
    // correctly so it just becomes a small phase shift in the cast.
    reg signed [BW-1:0] dx;
    reg signed [BW-1:0] dy;
    reg signed [BW-1:0] cos_at_angle_proc;
    reg signed [BW-1:0] sin_at_angle_proc;
    always @(posedge clk) begin
        dx                 <= cos_array[raycast_angle  >> 4];
        dy                 <= sin_array[raycast_angle  >> 4];
        cos_at_angle_proc  <= cos_array[angle_processed >> 4];
        sin_at_angle_proc  <= sin_array[angle_processed >> 4];
    end
    reg signed [BW-1:0] raycast_x = 0;
    reg signed [BW-1:0] raycast_y = 0;
    wire [7:0] map_index = (raycast_y >> BW_DEC)*world_width + (raycast_x >> BW_DEC);
    wire [BW-1:0] d_angle = oled_pixel_index < 48 ? (48 - oled_pixel_index) << BW_DEC : (oled_pixel_index-48) << BW_DEC;

    //wire signed [BW-1:0] raycast_x_delta = raycast_x < x ? (x - raycast_x) : (raycast_x - x);
    //wire signed [BW-1:0] raycast_y_delta = raycast_y < y ? (y - raycast_y) : (raycast_y - y);
    //wire [BW-1:0] dist_sq = (raycast_x_delta * raycast_x_delta) + (raycast_y_delta * raycast_y_delta);

    always @ (posedge clk) begin
        if (world_map[map_index] == 0) begin // && world_map_blue[map_index]==0) begin
            raycast_x <= raycast_x + (dx>>1);
            raycast_y <= raycast_y + (dy>>1);
            raycast_step <= raycast_step + 1;

            if (raycast_step > 50) begin
                raycast_step <= 0;
                raycast_x <= x;
                raycast_y <= y;
            end
        end else begin
           // trigger
           distance <= (
                raycast_step
                //* (abs_cos(d_angle) >> 3)
            ); //sqrt_array[dist_sq];
           raycast_step <= 0;
           raycast_x <= x;
           raycast_y <= y;
        end
    end

    always @ (posedge clk_100hz) begin

        if (btnL)  begin
            angle[16:8] <= angle[16:8] == 0 ? 360 : angle[16:8] - (1);
        end
        if (btnR)  begin
            angle[16:8] <= angle[16:8] == 360 ? 0 : angle[16:8]  + (1);
        end

        if (btnU)  begin
            x_precise <= x_precise + cos_at_angle_proc;
            y_precise <= y_precise + sin_at_angle_proc;
        end
        if (btnD)  begin
            x_precise <= x_precise - cos_at_angle_proc;
            y_precise <= y_precise - sin_at_angle_proc;
        end
    end

    ///////////////////////////////////////////////////////////////////
    // No initializer on the declaration — yosys/ECP5 cannot legalize an
    // initialized D-latch. Default-assign at the head of the always block.
    reg [15:0] pixel_data;
    assign oled_pixel_data = pixel_data;

    wire [7:0] colour_factor   = 8'd1 + (distance >> 2); // /4 reduced to >>2
    wire [7:0] inv_distance    = div64(distance[7:0]);   // 64/distance
    wire [4:0] shaded_r        = div31(colour_factor);   // 31/colour_factor
    wire [5:0] shaded_g        = div63(colour_factor);   // 63/colour_factor
    always @(*) begin
        pixel_data = 16'h0000;
        if (oled_ypos <= 32) begin
            pixel_data = constant.CYAN;
        end
        if (oled_ypos >= 32) begin
            pixel_data = constant.GREEN;
        end
        if (32 - inv_distance <= oled_ypos && oled_ypos <= 32 + inv_distance) begin
            pixel_data = {shaded_r, shaded_g, 5'b0};
        end
    end
endmodule
