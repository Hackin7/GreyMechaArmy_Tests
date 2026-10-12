// Streaming scene renderer. Coordinates follow the driver's sequential prefetch;
// no division by 240 and no RGB framebuffer are needed. Three-cycle pixel pipeline.
module paint_renderer (
    input wire clk, resetn,
    input wire [15:0] pixel_index,
    output reg [9:0] canvas_address,
    input wire [2:0] canvas_colour,
    input wire [6:0] cursor_x,
    input wire [5:0] cursor_y,
    input wire [2:0] chosen_colour,
    input wire [3:0] prediction,
    input wire prediction_valid, updating,
    output reg [15:0] pixel_data
);
    `include "font.vh"
    reg [15:0] previous_index;
    reg [7:0] x, y;
    wire scene = x >= 24 && x < 216 && y >= 56 && y < 184;
    wire [6:0] sx = (x-24) >> 1;
    wire [5:0] sy = (y-56) >> 1;
    wire canvas_area = scene && sx < 56 && sy < 56;
    wire [9:0] next_address = canvas_area ? (sy >> 1)*28 + (sx >> 1) : 10'd0;
    reg [15:0] colour;
    reg [7:0] ch;
    reg [7:0] ty;
    reg [7:0] position;
    reg [5:0] bit_offset;
    reg text_area;
    reg [2:0] swatch;
    reg [15:0] base_r;
    reg [7:0] ch_r;
    reg [5:0] bit_r;
    reg text_r;
    reg overlay, overlay_r, canvas_r;
    wire [34:0] glyph_r=glyph(ch_r);
    function [15:0] rgb(input [2:0] c);
        case(c)
            1: rgb=16'h001f;
            2: rgb=16'h07e0;
            3: rgb=16'hf800;
            4: rgb=16'hfda0;
            default: rgb=16'hffff;
        endcase
    endfunction
    function [7:0] title_char(input [4:0] n);
        case(n)
            0:title_char="M"; 1:title_char="N"; 2:title_char="I";
            3:title_char="S"; 4:title_char="T"; 5:title_char=" ";
            6:title_char="P"; 7:title_char="A"; 8:title_char="I";
            9:title_char="N"; 10:title_char="T";
            default:title_char=" ";
        endcase
    endfunction
    function [7:0] result_char(input [4:0] n);
        case(n)
            0:result_char="D"; 1:result_char="I"; 2:result_char="G";
            3:result_char="I"; 4:result_char="T"; 5:result_char=":";
            6:result_char=" ";
            7:result_char=prediction_valid ? (8'd48+{4'd0,prediction}) : "-";
            8:result_char=prediction_valid ? " " : "-";
            9:result_char=updating ? "*" : " ";
            default:result_char=" ";
        endcase
    endfunction
    function [7:0] legend_char(input [4:0] n);
        case(n)
            0:legend_char="A"; 1:legend_char=" "; 2:legend_char="D";
            3:legend_char="R"; 4:legend_char="A"; 5:legend_char="W";
            6:legend_char=" "; 7:legend_char="B"; 8:legend_char=" ";
            9:legend_char="C"; 10:legend_char="L"; 11:legend_char="E";
            12:legend_char="A"; 13:legend_char="R";
            default:legend_char=" ";
        endcase
    endfunction
    // Decode each caption from x in parallel. Selecting a row first would put
    // the y comparator before both the position lookup and character lookup.
    wire [7:0] title_offset=x-8'd54, result_offset=x-8'd60, legend_offset=x-8'd78;
    wire [7:0] title_position=font_position(title_offset[7:1]);
    wire [7:0] result_position=font_position(result_offset[7:1]);
    wire [7:0] legend_position=font_position(legend_offset[6:0]);
    wire [7:0] title_code=title_char(title_position[7:3]);
    wire [7:0] result_code=result_char(result_position[7:3]);
    wire [7:0] legend_code=legend_char(legend_position[7:3]);
    always @(posedge clk) begin
        if (!resetn) begin x<=0; y<=0; previous_index<=0; end
        else begin
            previous_index <= pixel_index;
            if (pixel_index == 0) begin x<=0; y<=0; end
            else if (pixel_index != previous_index) begin
                if (x == 239) begin x<=0; y<=y+1'b1; end
                else x<=x+1'b1;
            end
        end
        base_r <= colour;
        canvas_address <= next_address;
        overlay_r <= overlay;
        canvas_r <= canvas_area;
        ch_r <= ch;
        bit_r <= bit_offset;
        text_r <= text_area && position[2:0]<5 && ty<7;
        pixel_data <= (text_r && glyph_r[6'd34-bit_r]) ? 16'hffff :
                      overlay_r ? base_r : canvas_r ? rgb(canvas_colour) : 16'h0000;
    end
    always @* begin
        colour = 16'h0000;
        overlay = 0;
        swatch = 0;
        if (scene) begin
            if (sx>66 && sx<78 && sy>5 && sy<29) swatch=3;
            if (sx>80 && sx<92 && sy>5 && sy<29) swatch=1;
            if (sx>66 && sx<78 && sy>34 && sy<58) swatch=2;
            if (sx>80 && sx<92 && sy>34 && sy<58) swatch=4;
            if (swatch != 0) begin
                overlay = 1;
                colour = rgb(swatch);
                if (swatch == chosen_colour &&
                    (sx==67 || sx==77 || sx==81 || sx==91 ||
                     sy==6 || sy==28 || sy==35 || sy==57)) colour=16'hffff;
            end
            if (sx+1 >= cursor_x && sx <= cursor_x+1 &&
                sy+1 >= cursor_y && sy <= cursor_y+1) begin
                colour=16'hf81f; overlay=1;
            end
        end
        ch=" "; ty=0; position=8'h07; text_area=0;
        if (x>=54 && x<186 && y>=26 && y<40) begin
            ty=(y-26)>>1; position=title_position; ch=title_code;
            text_area=1;
        end else if (x>=60 && x<180 && y>=194 && y<208) begin
            ty=(y-194)>>1; position=result_position; ch=result_code;
            text_area=1;
        end else if (x>=78 && x<162 && y>=216 && y<223) begin
            ty=y-216; position=legend_position; ch=legend_code;
            text_area=1;
        end
        bit_offset={3'b000,ty[2:0]}+{1'b0,ty[2:0],2'b00}+{3'b000,position[2:0]};
    end
endmodule
