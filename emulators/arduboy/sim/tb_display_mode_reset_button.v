`timescale 1ns/1ps

module tb_display_mode_reset_button;
	reg clk = 1'b0;
	reg resetn = 1'b0;
	reg btn_n = 1'b1;
	wire mode_cycle_toggle;
	wire board_reset;
	integer failures = 0;

	always #5 clk = ~clk;

	display_mode_reset_button #(
		.HOLD_CYCLES(12),
		.DEBOUNCE_CYCLES(2)
	) uut (
		.clk(clk),
		.resetn(resetn),
		.btn_n(btn_n),
		.mode_cycle_toggle(mode_cycle_toggle),
		.board_reset(board_reset)
	);

	task expect_state(
		input expected_toggle,
		input expected_reset,
		input [8*40-1:0] label
	);
		begin
			if (mode_cycle_toggle !== expected_toggle ||
				board_reset !== expected_reset) begin
				$display("FAIL %0s: toggle=%b reset=%b expected=%b/%b",
					label, mode_cycle_toggle, board_reset,
					expected_toggle, expected_reset);
				failures = failures + 1;
			end
		end
	endtask

	task short_press;
		begin
			btn_n = 1'b0;
			repeat (8) @(posedge clk);
			btn_n = 1'b1;
			repeat (8) @(posedge clk);
		end
	endtask

	initial begin
		repeat (4) @(posedge clk);
		resetn = 1'b1;
		repeat (8) @(posedge clk);
		expect_state(1'b0, 1'b0, "idle");

		short_press();
		expect_state(1'b1, 1'b0, "first short press");

		short_press();
		expect_state(1'b0, 1'b0, "second short press");

		btn_n = 1'b0;
		repeat (10) @(posedge clk);
		expect_state(1'b0, 1'b0, "before long threshold");
		repeat (12) @(posedge clk);
		expect_state(1'b0, 1'b1, "long press held");

		btn_n = 1'b1;
		repeat (8) @(posedge clk);
		expect_state(1'b0, 1'b0, "long press release");

		if (failures == 0)
			$display("PASS: short presses cycle mode and long press resets without cycling");
		else
			$display("FAIL: %0d button-controller checks failed", failures);
		$finish(failures != 0);
	end
endmodule
