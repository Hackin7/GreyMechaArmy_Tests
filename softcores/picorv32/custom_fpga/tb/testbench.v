`timescale 1 ns / 1 ps

module testbench;
	reg clk = 1;
	reg resetn = 0;

	wire trap;
	wire passed;
	wire [7:0] leds;
	wire out_strobe;
	wire [7:0] out_byte;
	wire trace_valid;
	wire [35:0] trace_data;

	integer trace_file;
	integer cycle_counter = 0;

	always #5 clk = ~clk;

	initial begin
		repeat (100) @(posedge clk);
		resetn <= 1;
	end

	initial begin
		if ($test$plusargs("vcd")) begin
			$dumpfile("testbench.vcd");
			$dumpvars(0, testbench);
		end

		repeat (1000000) @(posedge clk);
		$display("TIMEOUT");
		$finish;
	end

	initial begin
		if ($test$plusargs("trace")) begin
			trace_file = $fopen("testbench.trace", "w");
			repeat (10) @(posedge clk);
			while (!trap) begin
				@(posedge clk);
				if (trace_valid)
					$fwrite(trace_file, "%x\n", trace_data);
			end
			$fclose(trace_file);
			$display("Finished writing testbench.trace.");
		end
	end

	picorv32_custom_soc dut (
		.clk        (clk        ),
		.resetn     (resetn     ),
		.trap       (trap       ),
		.leds       (leds       ),
		.out_strobe (out_strobe ),
		.out_byte   (out_byte   ),
		.passed     (passed     ),
		.trace_valid(trace_valid),
		.trace_data (trace_data )
	);

	always @(posedge clk) begin
		if (resetn)
			cycle_counter <= cycle_counter + 1;

		if (resetn && out_strobe) begin
			$write("%c", out_byte);
`ifndef VERILATOR
			$fflush();
`endif
		end

		if (resetn && trap) begin
			repeat (10) @(posedge clk);
			$display("TRAP after %1d clock cycles", cycle_counter);
			$display("LED state: 0x%02x", leds);
			if (passed) begin
				$display("ALL TESTS PASSED.");
				$finish;
			end else begin
				$display("ERROR!");
				if ($test$plusargs("noerror"))
					$finish;
				$stop;
			end
		end
	end
endmodule
