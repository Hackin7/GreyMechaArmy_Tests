`timescale 1ns/1ps
module tb_controls;
    reg clk=0; always #5 clk=~clk;
    reg resetn=0,frame_boundary=0;
    reg [2:0] buttons_n=7;
    wire enabled; wire [6:0] offset;
    camera_controls #(.DEBOUNCE_CYCLES(4)) dut(.*);
    task ticks(input integer n); repeat(n) @(negedge clk); endtask
    task boundary;
        frame_boundary=1; ticks(1); frame_boundary=0; ticks(1);
    endtask
    task press(input integer b);
        buttons_n[b]=0; ticks(12); buttons_n[b]=1; ticks(12);
    endtask
    integer i;
    initial begin
        ticks(3); resetn=1; ticks(4);
        if(enabled!==0 || offset!==16) $fatal(1,"Defaults");
        buttons_n[0]=0; ticks(1); buttons_n[0]=1; ticks(2);
        buttons_n[0]=0; ticks(1); buttons_n[0]=1; ticks(12);
        boundary(); if(enabled!==0) $fatal(1,"Bounce accepted");
        press(0); if(enabled!==0) $fatal(1,"Mid-frame toggle");
        boundary(); if(enabled!==1) $fatal(1,"Toggle missing");
        buttons_n[0]=0; ticks(100); boundary();
        if(enabled!==0) $fatal(1,"Hold should act once");
        ticks(100); boundary(); if(enabled!==0) $fatal(1,"Hold retriggered");
        buttons_n[0]=1; ticks(12);
        press(2); if(offset!==16) $fatal(1,"Mid-frame offset");
        boundary(); if(offset!==20) $fatal(1,"Increment");
        for(i=0;i<20;i=i+1) press(2);
        boundary(); if(offset!==64) $fatal(1,"Upper clamp");
        for(i=0;i<20;i=i+1) press(1);
        boundary(); if(offset!==0) $fatal(1,"Lower clamp");
        buttons_n=3'b001; ticks(12); buttons_n=7; ticks(12);
        boundary(); if(offset!==0) $fatal(1,"Opposing buttons");
        resetn=0; ticks(2); resetn=1; ticks(2);
        if(enabled!==0 || offset!==16) $fatal(1,"Reset defaults");
        $display("PASS controls: bounce, hold, limits, frame commits, reset"); $finish;
    end
    initial begin #100000; $fatal(1,"Timeout"); end
endmodule
