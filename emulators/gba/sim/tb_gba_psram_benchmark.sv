`timescale 1ns/1ps
module OSCG #(parameter DIV=6)(output wire OSC); assign OSC=0; endmodule
module gba_pll #(parameter CORE_DIV=20,FLASH_DIV=8)(input wire osc,reset,output reg core_clk=0,panel_clk=0,flash_clk=0,
               output wire locked);
    always #25 core_clk=~core_clk;
    always #(25.0*FLASH_DIV/CORE_DIV) flash_clk=~flash_clk;
    always #6.25 panel_clk=~panel_clk;
    assign locked=1;
endmodule
module tb_gba_psram_benchmark;
    tri [5:0] j1;
    tri [3:0] dq;
    tran(dq[0],j1[1]);tran(dq[1],j1[4]);tran(dq[2],j1[5]);tran(dq[3],j1[2]);
    reg corrupt=0;
    top #(.WORDS(16)) dut(.btn(5'b11111),.btn_grey_n(1'b1),.btn_red_n(1'b1),
        .host_sck(1'b0),.host_mosi(1'b0),.host_cs_n(1'b1),.pmod_j1(j1),.flash_miso(1'b0));
    aps6404_model model(.cs_n(j1[0]),.sck(j1[3]),.dq(dq),.corrupt_reads(corrupt));
    initial begin
        force dut.run=1;force dut.pause=0;
        wait(dut.state==5);@(negedge dut.clk);
        if(dut.errors!=0 || dut.word_index!=15 || dut.write_cycles==0 || dut.read_cycles==0)
            $fatal(1,"Hardware benchmark positive check failed");
        if(dut.status_pc[31:28]!=3 || dut.status_pc[27])$fatal(1,"Benchmark result encoding failed");
        force dut.ram_reset=1;repeat(10)@(negedge dut.clk);
        corrupt=1;release dut.ram_reset;
        wait(dut.state==5);@(negedge dut.clk);
        if(dut.errors!=16 || !dut.status_pc[27])$fatal(1,"Benchmark failed to detect corrupted reads");
        $display("PASS hardware benchmark: write/read phases, completion counters, all injected comparison errors detected");
        $finish;
    end
    initial begin #10000000;$fatal(1,"Hardware benchmark simulation timeout");end
endmodule
