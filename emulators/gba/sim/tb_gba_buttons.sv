`timescale 1ns/1ps
module tb_gba_buttons;
    reg clk=0,reset=1;always #5 clk=~clk;
    reg [4:0] btn=31;reg grey=1,red=1,inject=0;reg [9:0] injected=0;
    wire [9:0] keys;wire mode;wire [6:0] physical;
    gba_buttons #(.DEBOUNCE_CYCLES(3),.START_CYCLES(40)) dut(
        .clk(clk),.reset(reset),.btn_n(btn),.grey_n(grey),.red_n(red),
        .inject_enable(inject),.injected(injected),.keys(keys),.physical(physical),.mode_toggle(mode));
    task settle;repeat(9) @(negedge clk);endtask
    task check(input [9:0] expected);if(keys!==expected)$fatal(1,"Keys %h expected %h",keys,expected);endtask
    initial begin
        settle;reset=0;settle;check(0);
        grey=0;red=0;settle;check(3);grey=1;red=1;settle;
        btn[2]=0;settle;grey=0;red=0;settle;check(10'h300);
        grey=1;red=1;settle;btn[3]=0;settle;check(4);
        btn[3]=1;settle;btn[1]=0;settle;check(0);if(mode!==1)$fatal(1,"Viewport chord");
        btn=31;settle;check(0);repeat(45)@(negedge clk);check(0);
        btn[2]=0;settle;btn[2]=1;settle;check(8);repeat(45)@(negedge clk);check(0);
        btn=5'b00101;settle;check(10'hd0);btn=31;settle;
        inject=1;injected=10'h3ff;settle;check(10'h3ff);inject=0;settle;check(0);
        $display("PASS buttons: mapping, chords, Start pulse, viewport, injection");$finish;
    end
endmodule
