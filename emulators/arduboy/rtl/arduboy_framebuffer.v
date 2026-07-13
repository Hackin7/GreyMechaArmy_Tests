module arduboy_framebuffer (
	input  wire        wr_clk,
	input  wire        rd_clk,
	input  wire        rd_resetn,

	input  wire        host_we,
	input  wire [9:0]  host_addr,
	input  wire [7:0]  host_wdata,

	input  wire [15:0] panel_pixel_index,
	output reg  [15:0] panel_rgb
);
	localparam integer PANEL_W = 240;
	localparam integer VIEW_X  = 56;
	localparam integer VIEW_Y  = 88;
	localparam integer VIEW_W  = 128;
	localparam integer VIEW_H  = 64;

	reg [7:0] fb [0:1023];

	reg [7:0]  row;
	reg [7:0]  col;
	reg [15:0] last_pixel_index;
	reg [7:0]  next_row;
	reg [7:0]  next_col;
	reg [6:0]  ard_x;
	reg [5:0]  ard_y;
	reg [7:0]  rel_x;
	reg [7:0]  rel_y;
	reg [9:0]  fb_addr;
	reg [2:0]  fb_bit;
	reg        active;
	reg [7:0]  fb_rdata;
	reg [2:0]  fb_bit_d;
	reg        active_d;

	integer i;

	initial begin
		for (i = 0; i < 1024; i = i + 1)
			fb[i] = 8'h00;
	end

	always @(posedge wr_clk) begin
		if (host_we)
			fb[host_addr] <= host_wdata;
	end

	always @(posedge rd_clk) begin
		if (!rd_resetn) begin
			row <= 8'd0;
			col <= 8'd0;
			last_pixel_index <= 16'd0;
			fb_addr <= 10'd0;
			fb_bit <= 3'd0;
			active <= 1'b0;
			fb_rdata <= 8'h00;
			fb_bit_d <= 3'd0;
			active_d <= 1'b0;
			panel_rgb <= 16'h0000;
		end else begin
			if (panel_pixel_index != last_pixel_index) begin
				row <= next_row;
				col <= next_col;
				last_pixel_index <= panel_pixel_index;
				fb_addr <= {ard_y[5:3], ard_x};
				fb_bit <= ard_y[2:0];
				active <= (next_col >= VIEW_X) && (next_col < VIEW_X + VIEW_W) &&
					(next_row >= VIEW_Y) && (next_row < VIEW_Y + VIEW_H);
			end

			fb_rdata <= fb[fb_addr];
			fb_bit_d <= fb_bit;
			active_d <= active;
			panel_rgb <= (active_d && fb_rdata[fb_bit_d]) ? 16'hFFFF : 16'h0000;
		end
	end

	always @(*) begin
		if (panel_pixel_index == 16'd0 || panel_pixel_index < last_pixel_index) begin
			next_col = 8'd0;
			next_row = 8'd0;
		end else if (panel_pixel_index != last_pixel_index) begin
			if (col == PANEL_W - 1) begin
				next_col = 8'd0;
				next_row = row + 1'b1;
			end else begin
				next_col = col + 1'b1;
				next_row = row;
			end
		end else begin
			next_col = col;
			next_row = row;
		end

		rel_x = next_col - VIEW_X;
		rel_y = next_row - VIEW_Y;
		ard_x = rel_x[6:0];
		ard_y = rel_y[5:0];
	end
endmodule
