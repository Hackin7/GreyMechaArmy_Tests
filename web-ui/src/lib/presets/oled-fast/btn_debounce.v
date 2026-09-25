// Synchronize active-low buttons; btn_press[i]=1 when held stable pressed.
module btn_debounce #(
	parameter integer WIDTH = 5,
	parameter integer STABLE_CYCLES = 4096
) (
	input  wire              clk,
	input  wire              resetn,
	input  wire [WIDTH-1:0]  btn_n,
	output reg  [WIDTH-1:0]  btn_press
);
	localparam integer CW = 13;

	reg [1:0] sh [WIDTH-1:0];
	reg [WIDTH-1:0] sync;
	reg [WIDTH-1:0] stable;
	reg [CW-1:0] cnt;

	integer i;

	always @(posedge clk) begin
		for (i = 0; i < WIDTH; i = i + 1)
			sh[i] <= {sh[i][0], btn_n[i]};
	end

	always @(*) begin
		for (i = 0; i < WIDTH; i = i + 1)
			sync[i] = sh[i][1];
	end

	always @(posedge clk) begin
		if (!resetn) begin
			stable    <= {WIDTH{1'b1}};
			cnt       <= 0;
			btn_press <= {WIDTH{1'b0}};
		end else begin
			if (sync != stable) begin
				stable <= sync;
				cnt    <= 0;
			end else if (cnt < STABLE_CYCLES[CW-1:0])
				cnt <= cnt + 1'b1;
			if (sync == stable && cnt == STABLE_CYCLES[CW-1:0])
				btn_press <= ~stable;
		end
	end
endmodule
