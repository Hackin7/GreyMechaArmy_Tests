// A 5x7 font in a 160x12 black rectangle; white is invariant under R/B swap.
module isp_hud(
    input wire clk,resetn,start,take,
    input wire [2:0] mode,input wire enabled,input wire [15:0] value_q8,
    output wire [15:0] pixel
);
    reg [7:0] x;
    reg [3:0] y;
    reg [6:0] whole;
    reg [11:0] fraction_bcd;
    reg [3:0] tens,ones;
    reg [4:0] char_index;
    reg [2:0] column;
    reg [79:0] name;
    reg [7:0] ch,next_ch;
    reg [34:0] glyph,font_bits;
    reg [4:0] row_bits;
    reg [15:0] pixel_reg;
    always @* begin
        case(mode)
            0:name="OFFSET    ";1:name="GAMMA     ";2:name="CONTRAST  ";
            3:name="SATURATION";default:name="SOBEL     ";
        endcase
        next_ch=32;
        if(char_index<10) next_ch=name >> ((9-char_index)*8);
        else case(char_index)
            11:next_ch=tens!=0 ? 48+tens : 32;
            12:next_ch=48+ones;
            13:next_ch=mode==0 ? 32 : 46;
            14:next_ch=mode==0 ? 32 : 48+fraction_bcd[11:8];
            15:next_ch=mode==0 ? 32 : 48+fraction_bcd[7:4];
            16:next_ch=mode==0 ? 32 : 48+fraction_bcd[3:0];
            18:next_ch="O";19:next_ch=enabled ? "N" : "F";20:next_ch=enabled ? 32 : "F";
            default:next_ch=32;
        endcase
    end
    always @* begin
        (* rom_style="logic" *) case(ch)
            "A":font_bits=35'b01110_10001_10001_11111_10001_10001_10001;
            "B":font_bits=35'b11110_10001_10001_11110_10001_10001_11110;
            "C":font_bits=35'b01111_10000_10000_10000_10000_10000_01111;
            "E":font_bits=35'b11111_10000_10000_11110_10000_10000_11111;
            "F":font_bits=35'b11111_10000_10000_11110_10000_10000_10000;
            "G":font_bits=35'b01111_10000_10000_10111_10001_10001_01111;
            "I":font_bits=35'b11111_00100_00100_00100_00100_00100_11111;
            "L":font_bits=35'b10000_10000_10000_10000_10000_10000_11111;
            "M":font_bits=35'b10001_11011_10101_10101_10001_10001_10001;
            "N":font_bits=35'b10001_11001_10101_10011_10001_10001_10001;
            "O":font_bits=35'b01110_10001_10001_10001_10001_10001_01110;
            "R":font_bits=35'b11110_10001_10001_11110_10100_10010_10001;
            "S":font_bits=35'b01111_10000_10000_01110_00001_00001_11110;
            "T":font_bits=35'b11111_00100_00100_00100_00100_00100_00100;
            "U":font_bits=35'b10001_10001_10001_10001_10001_10001_01110;
            "0":font_bits=35'b01110_10001_10011_10101_11001_10001_01110;
            "1":font_bits=35'b00100_01100_00100_00100_00100_00100_01110;
            "2":font_bits=35'b01110_10001_00001_00010_00100_01000_11111;
            "3":font_bits=35'b11110_00001_00001_01110_00001_00001_11110;
            "4":font_bits=35'b00010_00110_01010_10010_11111_00010_00010;
            "5":font_bits=35'b11111_10000_10000_11110_00001_00001_11110;
            "6":font_bits=35'b01110_10000_10000_11110_10001_10001_01110;
            "7":font_bits=35'b11111_00001_00010_00100_01000_01000_01000;
            "8":font_bits=35'b01110_10001_10001_01110_10001_10001_01110;
            "9":font_bits=35'b01110_10001_10001_01111_00001_00001_01110;
            ".":font_bits=35'b00000_00000_00000_00000_00000_00110_00110;
            default:font_bits=0;
        endcase
    end
    assign pixel=pixel_reg;
    // Four registered rendering stages settle well before the next 32-clock pixel.
    always @(posedge clk) begin
        ch<=next_ch;glyph<=font_bits;
        row_bits<=glyph >> (34-(y-2)*5-4);
        pixel_reg<=(y>=2 && y<9 && column<5 && row_bits[4-column]) ? 16'hffff : 0;
        if(!resetn || start) begin
            x<=0;y<=0;column<=0;char_index<=0;whole<=value_q8[15:8];
            case(value_q8[7:5])
                0:fraction_bcd<=12'h000;1:fraction_bcd<=12'h125;
                2:fraction_bcd<=12'h250;3:fraction_bcd<=12'h375;
                4:fraction_bcd<=12'h500;5:fraction_bcd<=12'h625;
                6:fraction_bcd<=12'h750;7:fraction_bcd<=12'h875;
            endcase
            tens<=value_q8[15:8]>=60 ? 6 : value_q8[15:8]>=50 ? 5 :
                value_q8[15:8]>=40 ? 4 : value_q8[15:8]>=30 ? 3 :
                value_q8[15:8]>=20 ? 2 : value_q8[15:8]>=10 ? 1 : 0;
        end else if(take) begin
            if(x==159) begin x<=0;y<=y+1'b1;column<=0;char_index<=0;end
            else begin
                x<=x+1'b1;
                if(column==5) begin column<=0;char_index<=char_index+1'b1;end
                else column<=column+1'b1;
            end
        end
        ones<=whole-tens*10;
    end
endmodule