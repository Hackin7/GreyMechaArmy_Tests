`timescale 1ns/1ps
// Oscillator replacement for simulation of the complete board wrapper.
module OSCG #(parameter DIV=6)(output reg OSC=0);
    always #10 OSC=~OSC;
endmodule

module tb_top_wiring;
    reg reset_n=0, test_n=1;
    wire [7:0] led;
    wire host_miso;
    tri A10,A9,A8,A3,B10,B9,B8,A4;
    // Header vector ordered by the repository's LPF pin assignments.
    top dut(.btn_rst_n(reset_n),.btn_test_n(test_n),.led(led),
        .host_sck(1'b0),.host_mosi(1'b0),.host_cs_n(1'b1),
        .host_miso(host_miso),.pmod_j1({A4,B8,B9,B10,A3,A8,A9,A10}));
    // Independent board connection from the user's six physical-pin names.
    aps6404_model model(.cs_n(A10),.sck(A3),.dq({A8,B9,B10,A9}),.corrupt_reads(1'b0));
    integer transactions_after_test;
    initial begin
        #1; model.qpi_mode=1; // Requires all four SIO wires to be mapped correctly.
        #199; reset_n=1;
        #450000;
        if (led[4:0] !== 5'b10010)
            $fatal(1,"Physical-pin initialization/ID failed: LED=%h",led);
        if (B8 !== 1'bz || A4 !== 1'bz)
            $fatal(1,"Unused J1 pins are driven");
        test_n=0;
        #8000000;
        if (led[4:0] !== 5'b10110)
            $fatal(1,"Physical-pin button self-test failed: LED=%h",led);
        transactions_after_test=model.transactions;
        #1000000;
        if(model.transactions != transactions_after_test)
            $fatal(1,"Held button retriggered self-test");
        $display("PASS: complete top-level physical-pin wiring, QPI recovery, ID, debounced button self-test, held-button suppression");
        $finish;
    end
    initial begin #15000000; $fatal(1,"Top-level timeout"); end
endmodule
