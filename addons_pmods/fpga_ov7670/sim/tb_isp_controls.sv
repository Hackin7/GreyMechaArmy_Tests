`timescale 1ns/1ps
module tb_isp_controls;
    reg clk=0;always #5 clk=~clk;
    reg resetn=0,commit=0;
    reg [4:0] buttons_n=31;
    wire enabled;wire [2:0] mode;wire [39:0] presets;wire [15:0] value_q8;
    isp_controls #(.DEBOUNCE_CYCLES(4)) dut(.*);
    task settle;repeat(12) @(negedge clk);endtask
    task button(input [4:0] mask);
        buttons_n=~mask;settle;buttons_n=31;settle;
    endtask
    task latch;commit=1;@(negedge clk);commit=0;@(negedge clk);endtask
    integer i;
    initial begin
        settle;resetn=1;settle;
        if(enabled || mode!=0 || value_q8!=4096) $fatal(1,"Defaults");
        buttons_n=30;repeat(2) @(negedge clk);buttons_n=31;settle;latch;
        if(enabled) $fatal(1,"Bounce toggled");
        button(1);if(enabled) $fatal(1,"Committed mid-frame");latch;
        if(!enabled) $fatal(1,"Grey toggle");
        buttons_n=30;repeat(100) @(negedge clk);buttons_n=31;settle;latch;
        if(enabled) $fatal(1,"Hold repeated");
        button(16);latch;if(mode!=4 || value_q8!=256) $fatal(1,"Mode reverse wrap");
        button(8);latch;if(mode!=0) $fatal(1,"Mode forward wrap");
        button(4);latch;if(value_q8!=5120) $fatal(1,"Offset increment");
        button(8);latch;if(mode!=1 || value_q8!=384) $fatal(1,"Gamma default");
        for(i=0;i<25;i=i+1) button(4);latch;if(value_q8!=512) $fatal(1,"Gamma upper bound");
        for(i=0;i<25;i=i+1) button(2);latch;if(value_q8!=128) $fatal(1,"Gamma lower bound");
        button(6);latch;if(value_q8!=128) $fatal(1,"Opposing adjustments");
        button(12);latch;if(mode!=2 || value_q8!=320) $fatal(1,"Adjustment on mode event");
        button(24);latch;if(mode!=2) $fatal(1,"Opposing selection");
        for(i=0;i<25;i=i+1) button(4);latch;if(value_q8!=512) $fatal(1,"Contrast bound");
        button(8);latch;for(i=0;i<25;i=i+1) button(2);latch;
        if(value_q8!=0) $fatal(1,"Saturation bound");
        button(8);latch;for(i=0;i<25;i=i+1) button(4);latch;
        if(value_q8!=1024) $fatal(1,"Sobel bound");
        button(8);latch;if(value_q8!=5120) $fatal(1,"Remembered offset");
        resetn=0;settle;resetn=1;settle;
        if(enabled || mode || presets!=40'h030a0a0604) $fatal(1,"Reset defaults");
        $display("PASS ISP controls: debounce, hold, atomic commit, modes, remembered settings, limits, opposing presses");$finish;
    end
endmodule
