`timescale 1ns/1ps
module tb_isp_gamma;
    reg clk=0;always #5 clk=~clk;
    reg [3:0] preset=0;reg [7:0] r=0,g=0,b=0;
    wire [7:0] qr,qg,qb;
    reg [15:0] expected[0:2303];
    integer p,v;string dir,path;
    isp_gamma dut(.*);
    initial begin
        if(!$value$plusargs("VECTORS=%s",dir)) $fatal(1,"Vectors required");
        path={dir,"/gamma.hex"};$readmemh(path,expected);
        for(p=0;p<9;p=p+1) for(v=0;v<256;v=v+1) begin
            @(negedge clk);preset=p;r=v;g=255-v;b=v^85;
            @(posedge clk);#1;
            if(qr!==expected[p*256+v][7:0] || qg!==expected[p*256+255-v][7:0] || qb!==expected[p*256+(v^85)][7:0])
                $fatal(1,"Gamma preset %0d input %0d",p,v);
        end
        $display("PASS ISP gamma: all 256 inputs, all nine presets, three independent channels");$finish;
    end
endmodule
