`timescale 1ns/1ps
module tb_pins;
    reg clk=0;always #5 clk=~clk;
    reg resetn=0;
    reg [11:0] pins=12'h800;
    wire [191:0] counts;
    wire [11:0] levels,changed;
    camera_pin_monitor dut(.*);
    integer i,j;
    initial begin
        repeat(5) @(negedge clk);resetn=1;
        repeat(10) @(negedge clk);
        if(changed!=0 || counts!=0 || levels!=12'h800) $fatal(1,"Startup counted as activity");
        for(i=0;i<12;i=i+1) begin
            pins=0;repeat(5) @(negedge clk);
            for(j=0;j<i+1;j=j+1) begin
                pins=1<<i;repeat(5) @(negedge clk);
                pins=0;repeat(5) @(negedge clk);
            end
            if(counts[i*16+:16] != i+1) $fatal(1,"Pin %d count",i);
        end
        if(changed!=12'hfff) $fatal(1,"Missing sticky activity");
        resetn=0;repeat(5) @(negedge clk);
        if(changed!=0 || counts!=0) $fatal(1,"Reset");
        $display("PASS pins");$finish;
    end
endmodule
