`timescale 1ns/1ps
module tb_scan;
    reg clk=0; always #5 clk=~clk;
    reg resetn=0,enable=0,slave_low=0;
    wire scl_low,sda_low,complete;
    wire [6:0] address,first_ack;
    wire [7:0] ack_count;
    tri1 sda;
    wire scl=!scl_low;
    assign sda=(sda_low || slave_low) ? 1'b0 : 1'bz;
    camera_scan #(.QUARTER_CYCLES(4)) dut(.*,.sda_in(sda));
    integer bits=0,probes=0;
    reg active=0,respond=1;
    reg [7:0] received=0;
    always @(negedge sda) if(scl && resetn) begin active=1;bits=0;received=0;end
    always @(posedge sda) if(scl) begin active=0;slave_low=0;end
    always @(posedge scl) if(active) begin
        if(bits<8) received={received[6:0],sda};
        else if(bits==8) begin
            if(received !== ((7'h08+probes)<<1)) $fatal(1,"Address order %h",received);
            probes=probes+1;
        end
        bits=bits+1;
    end
    always @(negedge scl) slave_low=active && bits==8 && respond && received==8'h42;
    initial begin
        repeat(5) @(negedge clk);resetn=1;
        repeat(20) @(negedge clk);
        if(probes!=0) $fatal(1,"Scan before enable");
        enable=1;
        wait(complete); @(negedge clk);
        if(probes!=112 || ack_count!=1 || first_ack!=7'h21) $fatal(1,"ACK scan result");
        repeat(100) @(negedge clk);
        if(probes!=112) $fatal(1,"Repeated completed scan");
        resetn=0;enable=0;respond=0;probes=0;
        repeat(5) @(negedge clk);resetn=1;enable=1;
        wait(complete); @(negedge clk);
        if(ack_count!=0 || first_ack!=0 || probes!=112) $fatal(1,"NACK scan result");
        $display("PASS scan");$finish;
    end
    initial begin #2000000; $fatal(1,"Timeout");end
endmodule
