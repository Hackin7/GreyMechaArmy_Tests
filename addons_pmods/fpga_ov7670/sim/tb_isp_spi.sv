`timescale 1ns/1ps
module tb_isp_spi;
    reg clk=0;always #5 clk=~clk;
    reg resetn=0,enable=0,valid=0;
    reg [15:0] pixel=16'h1234;
    wire take,sclk,mosi,cs,done;wire [31:0] wait_cycles;
    isp_spi #(.PIXELS(3)) dut(.*);
    integer words=0,bits=0;reg [15:0] shift=0;
    always @(posedge sclk) if(!cs) begin
        shift={shift[14:0],mosi};bits=bits+1;
        if(bits==16) begin
            if(shift!==(words==0 ? 16'h1234 : words==1 ? 16'habcd : 16'h55aa)) $fatal(1,"Corrupt/starved SPI word");
            words=words+1;bits=0;
        end
    end
    initial begin
        repeat(5) @(negedge clk);resetn=1;enable=1;
        repeat(10) @(negedge clk);if(!cs || sclk) $fatal(1,"Started before valid");
        valid=1;wait(take);@(negedge clk);valid=0;
        wait(words==1);repeat(20) @(negedge clk);
        if(sclk || cs || words!=1) $fatal(1,"Starvation did not hold SCLK low");
        pixel=16'habcd;valid=1;wait(take);@(negedge clk);valid=0;
        wait(words==2);repeat(20) @(negedge clk);
        pixel=16'h55aa;valid=1;wait(done);@(negedge clk);
        if(!cs || sclk || words!=3 || bits!=0 || wait_cycles==0) $fatal(1,"Final SPI boundary");
        repeat(20) @(negedge clk);if(words!=3) $fatal(1,"Restarted after done");
        enable=0;@(negedge clk);enable=1;valid=0;repeat(4) @(negedge clk);
        if(!cs) $fatal(1,"Reset/rearm");
        $display("PASS ISP SPI: startup prefill, starvation, exact words, final bit, rearm");$finish;
    end
    initial begin #100000;$fatal(1,"SPI timeout");end
endmodule
