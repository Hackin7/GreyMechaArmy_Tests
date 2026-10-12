`timescale 1ns/1ps
module tb_inference;
    reg clk=0; always #20 clk=~clk;
    reg resetn=0, request=0;
    reg [783:0] snapshot=0;
    wire done;
    wire [3:0] digit;
    wire [31:0] cycles;
    reg image [0:4703];
    reg signed [63:0] expected [0:443];
    reg [3:0] digits [0:5];
    integer c=0,j,writes=0,elapsed;
    reg last_done=0;
    paint_inference dut(.clk(clk),.resetn(resetn),.request_toggle(request),
        .snapshot(snapshot),.done_toggle(done),.result_digit(digit),.result_cycles(cycles));
    always @(posedge clk) if(resetn && !dut.core_reset && dut.out_valid) begin
        if(dut.addr_out>=74) $fatal(1,"Invalid intermediate write");
        if(dut.val_out !== expected[c*74+dut.addr_out])
            $fatal(1,"Oracle mismatch case=%0d neuron=%0d got=%0d expected=%0d",c,
                   dut.addr_out,dut.val_out,expected[c*74+dut.addr_out]);
        writes=writes+1;
    end
    initial begin
        $readmemh("build/generated/images.mem",image);
        $readmemh("build/generated/expected.mem",expected);
        $readmemh("build/generated/digits.mem",digits);
        repeat(5) @(negedge clk); resetn=1;
        for(c=0;c<6;c=c+1) begin
            for(j=0;j<784;j=j+1) snapshot[j]=image[c*784+j];
            repeat(3) @(negedge clk);
            writes=0; request=~request; elapsed=0;
            while(done==last_done && elapsed<52000) begin @(negedge clk); elapsed=elapsed+1; end
            if(done==last_done || writes!=74 || cycles!=50903 || digit!==digits[c])
                $fatal(1,"Inference failed case=%0d writes=%0d cycles=%0d digit=%0d",c,writes,cycles,digit);
            last_done=done;
            $display("PASS inference case=%0d digit=%0d core_cycles=%0d request_cycles=%0d values=%0d",
                     c,digit,cycles,elapsed,writes);
            repeat(5) @(negedge clk);
        end
        $finish;
    end
    initial begin #15000000; $fatal(1,"Inference timeout"); end
endmodule
