// A short release cycles display scale. Holding the same button for the
// configured interval asserts board_reset until release. This controller is
// reset only by PLL lock so its long-press state survives the reset it creates.
module display_mode_reset_button #(
	parameter integer HOLD_CYCLES = 30000000,
	parameter integer DEBOUNCE_CYCLES = 4096
) (
	input  wire clk,
	input  wire resetn,
	input  wire btn_n,
	output reg  mode_cycle_toggle,
	output reg  board_reset
);
	localparam integer HOLD_COUNT_WIDTH = $clog2(HOLD_CYCLES + 1);

	wire button_pressed;
	reg [HOLD_COUNT_WIDTH-1:0] hold_count;
	reg long_press_seen;

	btn_debounce #(
		.WIDTH(1),
		.STABLE_CYCLES(DEBOUNCE_CYCLES)
	) u_debounce (
		.clk(clk),
		.resetn(resetn),
		.btn_n(btn_n),
		.btn_press(button_pressed)
	);

	always @(posedge clk) begin
		if (!resetn) begin
			hold_count <= 0;
			long_press_seen <= 1'b0;
			mode_cycle_toggle <= 1'b0;
			board_reset <= 1'b0;
		end else if (button_pressed) begin
			if (!long_press_seen) begin
				if (hold_count == HOLD_CYCLES - 1) begin
					long_press_seen <= 1'b1;
					mode_cycle_toggle <= 1'b0;
					board_reset <= 1'b1;
				end else begin
					hold_count <= hold_count + 1'b1;
				end
			end
		end else begin
			if (!long_press_seen && hold_count != 0)
				mode_cycle_toggle <= ~mode_cycle_toggle;
			hold_count <= 0;
			long_press_seen <= 1'b0;
			board_reset <= 1'b0;
		end
	end
endmodule
