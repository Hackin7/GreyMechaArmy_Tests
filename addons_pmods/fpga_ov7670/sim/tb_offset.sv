`timescale 1ns/1ps
module tb_offset;
    reg [15:0] pixel;
    reg enabled;
    reg [6:0] offset;
    wire [15:0] corrected;
    integer p,o,r,g,b;
    reg [15:0] expected;
    rgb_offset dut(.*);
    initial begin
        enabled=0; offset=64;
        for(p=0;p<65536;p=p+1) begin
            pixel=p; #1;
            if(corrected !== pixel) $fatal(1,"Bypass changed %h",pixel);
        end
        enabled=1;
        for(o=0;o<=64;o=o+4) begin
            offset=o;
            for(p=0;p<65536;p=p+1) begin
                pixel=p;
                r=((p>>11)&31)*8+((p>>13)&7);
                g=((p>>5)&63)*4+((p>>9)&3);
                b=(p&31)*8+((p>>2)&7);
                r=r>o?r-o:0; g=g>o?g-o:0; b=b>o?b-o:0;
                expected=((r>>3)<<11)|((g>>2)<<5)|(b>>3);
                #1;
                if(corrected !== expected)
                    $fatal(1,"Offset %0d pixel %h expected %h got %h",o,pixel,expected,corrected);
            end
        end
        $display("PASS offset: exhaustive RGB565 bypass and 17 offsets"); $finish;
    end
endmodule
