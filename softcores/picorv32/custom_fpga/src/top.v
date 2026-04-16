module top(
	input clk_ext,
	input [4:0] btn,
	output [7:0] led,
	inout [7:0] interconnect,
	inout [7:0] pmod_j1,
	inout [7:0] pmod_j2,
	output oled_scl,
	output oled_sda,
	output oled_dc,
	output oled_cs,
	output oled_rst,
	inout [4:0] s
);
	wire clk_int;
	defparam OSCI1.DIV = "5";
	OSCG OSCI1 (.OSC(clk_int));

	wire clk = clk_int;
	wire unused_clk_ext = clk_ext;
	wire reset_button = ~btn[0];

	reg [1:0] reset_sync = 2'b11;
	reg [7:0] reset_counter = 0;
	wire reset_request = reset_sync[1];
	wire resetn = &reset_counter;

	wire trap;
	wire passed;
	wire [7:0] led_value;
	wire out_strobe;
	wire [7:0] out_byte;
	wire trace_valid;
	wire [35:0] trace_data;
	wire unused_trap = trap;
	wire unused_passed = passed;
	wire unused_out_strobe = out_strobe;
	wire [7:0] unused_out_byte = out_byte;
	wire unused_trace_valid = trace_valid;
	wire [35:0] unused_trace_data = trace_data;

	always @(posedge clk) begin
		reset_sync <= {reset_sync[0], reset_button};
		if (reset_request)
			reset_counter <= 0;
		else if (!resetn)
			reset_counter <= reset_counter + 1;
	end

	picorv32_custom_soc soc (
		.clk        (clk        ),
		.resetn     (resetn     ),
		.trap       (trap       ),
		.leds       (led_value  ),
		.out_strobe (out_strobe ),
		.out_byte   (out_byte   ),
		.passed     (passed     ),
		.trace_valid(trace_valid),
		.trace_data (trace_data )
	);

	assign led = led_value;

	assign interconnect = 8'bz;
	assign pmod_j1 = 8'bz;
	assign pmod_j2 = 8'bz;
	assign s = 5'bz;

	assign oled_scl = 1'b0;
	assign oled_sda = 1'b0;
	assign oled_dc = 1'b0;
	assign oled_cs = 1'b0;
	assign oled_rst = resetn;
endmodule
