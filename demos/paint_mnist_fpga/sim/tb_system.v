`timescale 1ns/1ps
module tb_system;
    reg ui_clk=0; always #6.666 ui_clk=~ui_clk;
    reg nn_clk=0; always #20 nn_clk=~nn_clk;
    reg resetn=0;
    reg [5:0] buttons_n=6'b101111; // loader selection button is still held at boot
    reg [15:0] pixel_index=0;
    wire [15:0] pixel_data;
    wire [3:0] prediction;
    wire valid,busy,updating;
    reg signed [63:0] expected [0:443];
    reg [783:0] saved;
    reg first=1;
    integer writes=0;
    time started;
    paint_app #(.DEBOUNCE_CYCLES(3),.HOLD_CYCLES(10),.REPEAT_CYCLES(5),
                .INTERVAL_CYCLES(2000)) dut(
        .ui_clk(ui_clk),.nn_clk(nn_clk),.resetn_ui(resetn),.resetn_nn(resetn),
        .buttons_n(buttons_n),.pixel_index(pixel_index),.pixel_data(pixel_data),
        .prediction(prediction),.prediction_valid(valid),.busy(busy),.updating(updating));
    always @(posedge nn_clk) if(first && resetn && dut.inference.out_valid && !dut.inference.core_reset) begin
        if(dut.inference.val_out!==expected[5*74+dut.inference.addr_out])
            $fatal(1,"System snapshot oracle mismatch neuron=%0d",dut.inference.addr_out);
        writes=writes+1;
    end
    initial begin
        $readmemh("build/generated/expected.mem",expected);
        repeat(8) @(negedge ui_clk); resetn=1;
        wait(!dut.ui.clearing); repeat(5) @(negedge ui_clk);
        if(dut.ui.armed || dut.ui.dirty || busy || dut.ui.canvas[406]!=0)
            $fatal(1,"Held loader A caused an accidental startup stroke");
        buttons_n[4]=1; repeat(12) @(negedge ui_clk);
        buttons_n[4]=0; started=$time;
        wait(dut.ui.in_flight); @(negedge ui_clk); saved=dut.snapshot;
        if(saved!==(784'b1<<406)) $fatal(1,"Cursor/palette polluted initial one-cell image");
        // Continue drawing in a different cell while the first NN reads its frozen image.
        buttons_n[3]=0;
        repeat(100) @(negedge ui_clk);
        buttons_n[3]=1; buttons_n[4]=1;
        if(saved!==dut.snapshot || !dut.ui.dirty) $fatal(1,"In-flight drawing/snapshot isolation failed");
        wait(valid); @(negedge ui_clk);
        if(writes!=74 || dut.result_cycles!=50903) $fatal(1,"System inference schedule failed");
        $display("PASS system first_digit=%0d core_cycles=%0d stroke_to_result_ns=%0d values=%0d",
                 prediction,dut.result_cycles,$time-started,writes);
        first=0;
        wait(dut.ui.in_flight); @(negedge ui_clk);
        buttons_n[5]=0; repeat(12) @(negedge ui_clk); buttons_n[5]=1;
        wait(!dut.ui.clearing);
        wait(!busy); repeat(10) @(negedge ui_clk);
        if(valid) $fatal(1,"System clear admitted stale result");
        $display("PASS system continuous dirty refresh and clear across independent clocks");
        $finish;
    end
    initial begin #8000000; $fatal(1,"System timeout"); end
endmodule
