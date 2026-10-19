`timescale 1ns/1ps
module tb_debug #(parameter WIDTH=256);
    reg clk=0;always #5 clk=~clk;
    reg resetn=0,sck=0,cs_n=1,pclk=0,href=0,vsync=0;
    reg [WIDTH-1:0] status={2{256'h43414d3212345678deadbeef00000001abcd123400000000ffffffff12345678}};
    wire miso;
    wire [31:0] pclk_edges,frames;
    wire [9:0] last_lines;
    wire [11:0] last_bytes;
    reg [WIDTH-1:0] received,expected;
    integer n;
    camera_debug #(.STATUS_BITS(WIDTH)) dut(.*);
    camera_monitor monitor(.*);
    task transfer;
        expected=status;cs_n=0;#100;
        for(n=WIDTH-1;n>=0;n=n-1) begin
            sck=1;#100;received[n]=miso;sck=0;#100;
            if(n==128) status=~status;
        end
        cs_n=1;#100;
        if(received!==expected) $fatal(1,"Debug SPI snapshot changed or bit shifted");
    endtask
    task row(input integer bytes_count);
        integer b;
        href=1;#100;
        for(b=0;b<bytes_count;b=b+1) begin pclk=1;#50;pclk=0;#50;end
        href=0;#150;
    endtask
    initial begin
        #100;resetn=1;#100;
        transfer();transfer();
        vsync=1;#150;vsync=0;#150;
        row(8);row(6);row(8);
        vsync=1;#150;
        if(pclk_edges!==22 || frames!==2 || last_lines!==3 || last_bytes!==8)
            $fatal(1,"Monitor counts: edges=%d frames=%d lines=%d bytes=%d",pclk_edges,frames,last_lines,last_bytes);
        $display("PASS debug: atomic SPI snapshots and asynchronous DVP geometry/activity");$finish;
    end
    initial begin #1000000;$fatal(1,"Debug timeout");end
endmodule
