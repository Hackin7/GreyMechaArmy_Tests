`timescale 1ns/1ps

module tb_framebuffer_scaling;
	reg clk = 1'b0;
	reg rd_resetn = 1'b0;
	reg host_we = 1'b0;
	reg [9:0] host_addr = 10'd0;
	reg [7:0] host_wdata = 8'd0;
	reg [1:0] scale_mode = 2'd0;
	reg [15:0] panel_pixel_index = 16'd0;
	wire [15:0] panel_rgb;
	integer failures = 0;
	integer pix;

	always #5 clk = ~clk;

	arduboy_framebuffer uut (
		.wr_clk(clk),
		.rd_clk(clk),
		.rd_resetn(rd_resetn),
		.host_we(host_we),
		.host_addr(host_addr),
		.host_wdata(host_wdata),
		.scale_mode(scale_mode),
		.panel_pixel_index(panel_pixel_index),
		.panel_rgb(panel_rgb)
	);

	task write_byte(input [9:0] addr, input [7:0] value);
		begin
			@(negedge clk);
			host_addr = addr;
			host_wdata = value;
			host_we = 1'b1;
			@(negedge clk);
			host_we = 1'b0;
		end
	endtask

	task begin_mode(input [1:0] mode);
		begin
			rd_resetn = 1'b0;
			panel_pixel_index = 16'd0;
			scale_mode = mode;
			repeat (6) @(posedge clk);
			rd_resetn = 1'b1;
			repeat (4) @(posedge clk);
			// Present a registered frame wrap so the requested mode is latched.
			panel_pixel_index = 16'd1;
			repeat (6) @(posedge clk);
			panel_pixel_index = 16'd0;
			repeat (8) @(posedge clk);
		end
	endtask

	task check_pixel(
		input integer pixel,
		input [15:0] expected,
		input [8*48-1:0] label
	);
		begin
			if (panel_rgb !== expected) begin
				$display("FAIL %0s pixel=%0d got=%04x expected=%04x",
					label, pixel, panel_rgb, expected);
				failures = failures + 1;
			end
		end
	endtask

	task scan_1x;
		begin
			begin_mode(2'd0);
			for (pix = 0; pix < 57600; pix = pix + 1) begin
				panel_pixel_index = pix[15:0];
				repeat (6) @(posedge clk);
				if (pix == 88 * 240 + 55)
					check_pixel(pix, 16'h0000, "1x left border");
				if (pix == 88 * 240 + 56)
					check_pixel(pix, 16'hffff, "1x source x0");
				if (pix == 88 * 240 + 57)
					check_pixel(pix, 16'h0000, "1x source x1");
				if (pix == 88 * 240 + 60)
					check_pixel(pix, 16'hffff, "1x source x4");
			end
		end
	endtask

	task scan_1p5x;
		begin
			begin_mode(2'd1);
			for (pix = 0; pix < 57600; pix = pix + 1) begin
				panel_pixel_index = pix[15:0];
				repeat (6) @(posedge clk);
				if (pix == 72 * 240 + 23)
					check_pixel(pix, 16'h0000, "1.5x left border");
				if (pix == 72 * 240 + 24 || pix == 72 * 240 + 25)
					check_pixel(pix, 16'hffff, "1.5x source x0 repeat");
				if (pix == 72 * 240 + 26)
					check_pixel(pix, 16'h0000, "1.5x source x1");
				if (pix == 72 * 240 + 30 || pix == 72 * 240 + 31)
					check_pixel(pix, 16'hffff, "1.5x source x4 repeat");
				if (pix == 73 * 240 + 24)
					check_pixel(pix, 16'hffff, "1.5x source y0 repeat");
				if (pix == 74 * 240 + 24)
					check_pixel(pix, 16'h0000, "1.5x source y1");
			end
		end
	endtask

	task scan_2x;
		begin
			begin_mode(2'd2);
			for (pix = 0; pix < 57600; pix = pix + 1) begin
				panel_pixel_index = pix[15:0];
				repeat (6) @(posedge clk);
				if (pix == 55 * 240)
					check_pixel(pix, 16'h0000, "2x top border");
				if (pix == 56 * 240 || pix == 56 * 240 + 1 ||
					pix == 57 * 240 || pix == 57 * 240 + 1)
					check_pixel(pix, 16'hffff, "2x centered source x4/y0");
				if (pix == 56 * 240 + 2)
					check_pixel(pix, 16'h0000, "2x source x5");
			end
		end
	endtask

	initial begin
		repeat (4) @(posedge clk);
		// White markers at source (0,0) and (4,0); all other pixels stay black.
		write_byte(10'd0, 8'h01);
		write_byte(10'd4, 8'h01);

		scan_1x();
		scan_1p5x();
		scan_2x();

		if (failures == 0)
			$display("PASS: 1x, 1.5x, and centered 2x framebuffer scaling");
		else
			$display("FAIL: %0d framebuffer scaling checks failed", failures);
		$finish(failures != 0);
	end
endmodule
