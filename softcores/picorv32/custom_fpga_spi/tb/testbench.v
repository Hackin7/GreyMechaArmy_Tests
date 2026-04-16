`timescale 1 ns / 1 ps

/* Minimal SoC testbench: UART output, trap, optional VCD/trace. No SPI golden stream. */
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

	wire spi_sclk;
	wire spi_mosi;
	wire spi_cs_n;
	wire spi_dc;
	wire spi_rst_n;

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

		#(5_000_000_000);
		$display("TIMEOUT after 5 s simulation time");
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
		.clk         (clk         ),
		.resetn      (resetn      ),
		.trap        (trap        ),
		.leds        (leds        ),
		.out_strobe  (out_strobe  ),
		.out_byte    (out_byte    ),
		.passed      (passed      ),
		.trace_valid (trace_valid ),
		.trace_data  (trace_data  ),
		.spi_sclk    (spi_sclk    ),
		.spi_mosi    (spi_mosi    ),
		.spi_cs_n    (spi_cs_n    ),
		.spi_dc      (spi_dc      ),
		.spi_rst_n   (spi_rst_n   )
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
