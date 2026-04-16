// SPI mode 0 master (CPOL=0, CPHA=0): MSB first, MOSI + SCLK + active-low CS.
// One byte per transaction started by pulse on `start`. Between bytes, software
// may hold CS low using `keep_cs` so the next `start` does not glitch CS.

module simple_spi_master (
	input             clk,
	input             resetn,
	input      [ 7:0] clk_div,
	input      [ 7:0] tx_data,
	input             start,
	input             release_cs,
	input             keep_cs,
	input             idle_cs_n,
	input             dc_in,
	input             rst_n_in,
	output reg        busy,
	output reg        done,
	output reg        sclk,
	output reg        mosi,
	output reg        cs_n,
	output reg        dc,
	output reg        rst_n
);
	reg        active;
	reg [ 2:0] bit_i;
	reg        phase; // 0 = SCLK low half, 1 = SCLK high half
	reg [ 7:0] latched_tx;
	reg [ 7:0] divcnt;

	always @(posedge clk) begin
		if (!resetn) begin
			busy       <= 0;
			done       <= 0;
			sclk       <= 0;
			mosi       <= 0;
			cs_n       <= 1;
			dc         <= 0;
			rst_n      <= 0;
			active     <= 0;
			bit_i      <= 0;
			phase      <= 0;
			latched_tx <= 0;
			divcnt     <= 0;
		end else begin
			done  <= 0;
			dc    <= dc_in;
			rst_n <= rst_n_in;

			if (!active) begin
				sclk <= 0;
				if (release_cs)
					cs_n <= idle_cs_n;
				if (start && !busy) begin
					busy       <= 1;
					active     <= 1;
					bit_i      <= 3'd7;
					phase      <= 0;
					latched_tx <= tx_data;
					mosi       <= tx_data[7];
					sclk       <= 0;
					cs_n       <= 0;
					divcnt     <= clk_div;
				end
			end else begin
				if (divcnt != 0)
					divcnt <= divcnt - 1;
				else begin
					divcnt <= clk_div;
					if (!phase) begin
						sclk   <= 1;
						phase  <= 1;
					end else begin
						sclk <= 0;
						if (bit_i == 0) begin
							active <= 0;
							busy   <= 0;
							done   <= 1;
							if (!keep_cs)
								cs_n <= idle_cs_n;
						end else begin
							bit_i  <= bit_i - 3'd1;
							mosi   <= latched_tx[bit_i - 3'd1];
							phase  <= 0;
						end
					end
				end
			end
		end
	end
endmodule
