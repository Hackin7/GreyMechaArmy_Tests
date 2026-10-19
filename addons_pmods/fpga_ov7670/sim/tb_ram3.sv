`timescale 1ns/1ps
module tb_ram3;
    reg clk=0;always #5 clk=~clk;
    reg pclk=0;always #13 pclk=~pclk;
    reg write_enable=0;
    reg [1:0] write_bank=0,read_bank=0;
    reg [14:0] write_address=0,read_address=0;
    reg [15:0] write_data=0;
    wire [15:0] read_data;
    integer b,a;
    camera_ram3 dut(.*);
    function [15:0] pattern(input integer bank,address);
        pattern=16'hf0a5^(bank*16391+address*17);
    endfunction
    initial begin
        for(b=0;b<3;b=b+1) begin
            for(a=0;a<19200;a=a+1) begin
                @(negedge pclk);write_enable=1;write_bank=b;write_address=a;write_data=pattern(b,a);
            end
            @(negedge pclk);write_enable=0;
        end
        for(b=0;b<3;b=b+1) begin
            read_bank=b;
            for(a=0;a<19200;a=a+1) begin
                @(negedge clk);read_address=a;repeat(3) @(negedge clk);
                if(read_data !== pattern(b,a)) $fatal(1,"Bank %d address %d expected %h got %h",b,a,pattern(b,a),read_data);
            end
        end
        $display("PASS ram3: all 57600 words, chunk edges, distributed tail, three-cycle reads");$finish;
    end
    initial begin #10000000;$fatal(1,"Timeout");end
endmodule
