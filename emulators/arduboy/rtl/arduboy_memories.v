module arduboy_program_flash (
	input  wire        clk,
	input  wire        host_we,
	input  wire [14:0] host_addr,
	input  wire [7:0]  host_wdata,
	input  wire [13:0] cpu_word_addr,
	output reg  [15:0] cpu_instr
);
	reg [7:0] mem [0:32767];
	wire [14:0] cpu_byte_addr = {cpu_word_addr, 1'b0};

	always @(posedge clk) begin
		if (host_we)
			mem[host_addr] <= host_wdata;
		cpu_instr <= {mem[cpu_byte_addr + 1'b1], mem[cpu_byte_addr]};
	end
endmodule

module arduboy_sram (
	input  wire        clk,
	input  wire        re,
	input  wire        we,
	input  wire [11:0] addr,
	output reg  [7:0]  rdata,
	input  wire [7:0]  wdata
);
	reg [7:0] mem [0:4095];
	integer i;

	initial begin
		for (i = 0; i < 4096; i = i + 1)
			mem[i] = 8'h00;
	end

	always @(posedge clk) begin
		if (we)
			mem[addr] <= wdata;
		if (re)
			rdata <= mem[addr];
	end
endmodule

module arduboy_eeprom (
	input  wire       clk,
	input  wire       host_we,
	input  wire [9:0] host_addr,
	input  wire [7:0] host_wdata,
	input  wire       cpu_we,
	input  wire [9:0] cpu_addr,
	input  wire [7:0] cpu_wdata,
	output reg  [7:0] cpu_rdata
);
	reg [7:0] mem [0:1023];
	integer i;

	initial begin
		for (i = 0; i < 1024; i = i + 1)
			mem[i] = 8'hFF;
	end

	always @(posedge clk) begin
		if (host_we)
			mem[host_addr] <= host_wdata;
		if (cpu_we)
			mem[cpu_addr] <= cpu_wdata;
		cpu_rdata <= mem[cpu_addr];
	end
endmodule

module arduboy_fx_cache (
	input  wire        clk,
	input  wire        resetn,
	input  wire        host_we,
	input  wire [3:0]  host_slot,
	input  wire [7:0]  host_offset,
	input  wire [7:0]  host_wdata,
	input  wire        host_tag_we,
	input  wire [23:0] host_tag,

	input  wire [23:0] cpu_page,
	input  wire [7:0]  cpu_offset,
	input  wire        cpu_req,
	output reg  [7:0]  cpu_rdata,
	output reg         cpu_hit,
	output reg         request_pending
);
	reg [7:0] data [0:4095];
	reg [23:0] tag [0:15];
	reg [15:0] valid;
	reg [3:0] lookup_slot;

	integer i;

	always @(*) begin
		lookup_slot = cpu_page[3:0];
	end

	always @(posedge clk) begin
		if (!resetn) begin
			valid <= 16'h0000;
			request_pending <= 1'b0;
			for (i = 0; i < 16; i = i + 1)
				tag[i] <= 24'h000000;
		end else begin
			if (host_we)
				data[{host_slot, host_offset}] <= host_wdata;
			if (host_tag_we) begin
				tag[host_slot] <= host_tag;
				valid[host_slot] <= 1'b1;
				request_pending <= 1'b0;
			end

			cpu_rdata <= data[{lookup_slot, cpu_offset}];
			cpu_hit <= cpu_req && valid[lookup_slot] && (tag[lookup_slot] == cpu_page);
			if (cpu_req && !(valid[lookup_slot] && (tag[lookup_slot] == cpu_page)))
				request_pending <= 1'b1;
		end
	end
endmodule
