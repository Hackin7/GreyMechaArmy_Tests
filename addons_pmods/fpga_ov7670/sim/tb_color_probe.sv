`timescale 1ns/1ps
module tb_color_probe;
    reg clk=0;always #5 clk=~clk;
    reg pclk=0;always #17 pclk=~pclk;
    reg resetn=0,presetn=0,write_enable=0,frame_toggle=0;
    reg [14:0] write_address=0;
    reg [15:0] write_data=0;
    wire [127:0] samples;
    integer i;
    camera_color_probe dut(.*);
    task frame(input integer seed,input integer length);
        integer k;
        for(k=0;k<length;k=k+1) begin
            @(negedge pclk);write_enable=1;write_address=10+20*k;write_data=seed+k;
        end
        @(negedge pclk);write_enable=0;
        @(negedge pclk);frame_toggle=!frame_toggle;
        repeat(10) @(negedge pclk);
    endtask
    task check(input integer seed);
        for(i=0;i<8;i=i+1)
            if(samples[127-i*16-:16]!==16'(seed+i)) $fatal(1,"Probe order/CDC at %d",i);
    endtask
    initial begin
        repeat(5) @(negedge pclk);resetn=1;presetn=1;
        frame('hf800,8);check('hf800);
        frame('h07e0,7);check('hf800); // incomplete probe cannot replace complete values
        frame('h001f,8);check('h001f);
        presetn=0;resetn=0;repeat(5) @(negedge clk);
        if(samples!==0) $fatal(1,"Probe reset");
        $display("PASS color_probe: raw word order, bundled-data handshake, incomplete samples, reset");$finish;
    end
    initial begin #100000;$fatal(1,"Timeout");end
endmodule
