module arduboy_framebuffer (
	input  wire        wr_clk,
	input  wire        rd_clk,
	input  wire        rd_resetn,

	input  wire        host_we,
	input  wire [9:0]  host_addr,
	input  wire [7:0]  host_wdata,

	input  wire [1:0]  scale_mode,
	input  wire [15:0] panel_pixel_index,
	output reg  [15:0] panel_rgb
);
	localparam integer PANEL_W = 240;
	localparam [1:0] SCALE_1X   = 2'd0;
	localparam [1:0] SCALE_1P5X = 2'd1;
	localparam [1:0] SCALE_2X   = 2'd2;

	reg [7:0] fb [0:1023];

	reg [7:0]  row;
	reg [7:0]  col;
	reg [15:0] last_pixel_index;
	reg        pixel_advance;
	reg        frame_restart;
	reg [1:0]  active_scale_mode;
	reg [6:0]  ard_x;
	reg [5:0]  ard_y;
	reg [6:0]  scale_1p5_x;
	reg [5:0]  scale_1p5_y;
	reg [1:0]  scale_1p5_x_phase;
	reg [1:0]  scale_1p5_y_phase;
	reg        coord_active;
	reg        coord_valid;
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
			pixel_advance <= 1'b0;
			frame_restart <= 1'b0;
			active_scale_mode <= SCALE_1X;
			scale_1p5_x <= 7'd0;
			scale_1p5_y <= 6'd0;
			scale_1p5_x_phase <= 2'd0;
			scale_1p5_y_phase <= 2'd0;
			fb_addr <= 10'd0;
			fb_bit <= 3'd0;
			active <= 1'b0;
			coord_valid <= 1'b0;
			fb_rdata <= 8'h00;
			fb_bit_d <= 3'd0;
			active_d <= 1'b0;
			panel_rgb <= 16'h0000;
		end else begin
			// Register stream movement before updating raster coordinates. This
			// breaks the live pixel-index comparison out of the coordinate path.
			pixel_advance <= (panel_pixel_index != last_pixel_index);
			if (panel_pixel_index != last_pixel_index) begin
				last_pixel_index <= panel_pixel_index;
				frame_restart <= (panel_pixel_index == 16'd0) ||
					(panel_pixel_index < last_pixel_index);
			end

			coord_valid <= pixel_advance;
			if (pixel_advance) begin
				if (frame_restart) begin
					row <= 8'd0;
					col <= 8'd0;
					active_scale_mode <= scale_mode;
					scale_1p5_x <= 7'd0;
					scale_1p5_y <= 6'd0;
					scale_1p5_x_phase <= 2'd0;
					scale_1p5_y_phase <= 2'd0;
				end else if (col == PANEL_W - 1) begin
					col <= 8'd0;
					row <= row + 1'b1;

					// The new row is 72: reset the vertical phase.
					if (row == 8'd71) begin
						scale_1p5_y <= 6'd0;
						scale_1p5_y_phase <= 2'd0;
					end else if (row >= 8'd72 && row < 8'd167) begin
						if (scale_1p5_y_phase == 2'd0) begin
							scale_1p5_y_phase <= 2'd1;
						end else begin
							scale_1p5_y <= scale_1p5_y + 1'b1;
							scale_1p5_y_phase <=
								(scale_1p5_y_phase == 2'd2) ? 2'd0 : 2'd2;
						end
					end
				end else begin
					col <= col + 1'b1;

					// The new column is 24: reset the horizontal phase.
					if (col == 8'd23) begin
						scale_1p5_x <= 7'd0;
						scale_1p5_x_phase <= 2'd0;
					end else if (col >= 8'd24 && col < 8'd215) begin
						if (scale_1p5_x_phase == 2'd0) begin
							scale_1p5_x_phase <= 2'd1;
						end else begin
							scale_1p5_x <= scale_1p5_x + 1'b1;
							scale_1p5_x_phase <=
								(scale_1p5_x_phase == 2'd2) ? 2'd0 : 2'd2;
						end
					end
				end
			end

			// Raster tracking is registered one cycle before address/viewport
			// decoding. The OLED streamer provides six prefetch clocks.
			if (coord_valid) begin
				fb_addr <= {ard_y[5:3], ard_x};
				fb_bit <= ard_y[2:0];
				active <= coord_active;
			end

			fb_rdata <= fb[fb_addr];
			fb_bit_d <= fb_bit;
			active_d <= active;
			panel_rgb <= (active_d && fb_rdata[fb_bit_d]) ? 16'hFFFF : 16'h0000;
		end
	end

	always @(*) begin
		// Exact three-phase 1.5x raster mapping without a divider.
		ard_x = 7'd0;
		ard_y = 6'd0;
		coord_active = 1'b0;

		case (active_scale_mode)
			SCALE_1P5X: begin
				// 192x96 nearest-neighbour mapping from the phase accumulators.
				coord_active = (col >= 8'd24) && (col < 8'd216) &&
					(row >= 8'd72) && (row < 8'd168);
				ard_x = scale_1p5_x;
				ard_y = scale_1p5_y;
			end
			SCALE_2X: begin
				// 256x128 does not fit the 240-pixel panel. Crop eight scaled
				// pixels per side (four source columns) to remain centered.
				coord_active = (row >= 8'd56) && (row < 8'd184);
				ard_x = (col + 8'd8) >> 1;
				ard_y = (row - 8'd56) >> 1;
			end
			default: begin
				// 128x64 centered on the 240x240 panel.
				coord_active = (col >= 8'd56) && (col < 8'd184) &&
					(row >= 8'd88) && (row < 8'd152);
				ard_x = col - 8'd56;
				ard_y = row - 8'd88;
			end
		endcase
	end
endmodule
