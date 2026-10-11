`timescale 1ns/1ps
`default_nettype none
module tb_gba_smoke;
 reg clk=0; always #5 clk=~clk;
 reg reset_n=0; reg [11:0] bios_wraddr=0; reg [31:0] bios_wrdata=0; reg bios_wr=0;
 wire rom_read,rom_done,ext_read_not_write,ext_request,ext_done,pixel_we;
 wire [24:0] rom_addr; wire [25:0] ext_addr; wire [31:0] rom_data,rom_second_data;
 wire [31:0] ext_write_data,ext_read_data,debug_cpu_pc;
 wire [7:0] pixel_x,pixel_y; wire [15:0] pixel_addr,audio_left,audio_right;
 wire [17:0] pixel_data; reg [31:0] bios[0:4095]; integer i; integer cycles=0;
 gba_core_wrapper dut(.clk_100(clk),.reset_n(reset_n),
  .key_a(1'b0),.key_b(1'b0),.key_select(1'b0),.key_start(1'b0),
  .key_right(1'b0),.key_left(1'b0),.key_up(1'b0),.key_down(1'b0),
  .key_r(1'b0),.key_l(1'b0),.max_rom_addr(25'd0),.flash_1m(1'b0),
  .rom_read(rom_read),.rom_addr(rom_addr),.rom_done(rom_done),.rom_data(rom_data),
  .rom_second_data(rom_second_data),.ext_write_data(ext_write_data),
  .ext_read_data(ext_read_data),.ext_addr(ext_addr),.ext_read_not_write(ext_read_not_write),
  .ext_request(ext_request),.ext_done(ext_done),.bios_wraddr(bios_wraddr),
  .bios_wrdata(bios_wrdata),.bios_wr(bios_wr),.pixel_x(pixel_x),.pixel_y(pixel_y),
  .pixel_addr(pixel_addr),.pixel_data(pixel_data),.pixel_we(pixel_we),
  .audio_left(audio_left),.audio_right(audio_right),.debug_cpu_pc(debug_cpu_pc));
 gba_sim_memory mem(.clk(clk),.rom_read(rom_read),.rom_addr(rom_addr),.rom_done(rom_done),
  .rom_data(rom_data),.rom_second_data(rom_second_data),.ext_write_data(ext_write_data),
  .ext_read_data(ext_read_data),.ext_addr(ext_addr),.ext_read_not_write(ext_read_not_write),
  .ext_request(ext_request),.ext_done(ext_done));
 initial begin
  for(i=0;i<4096;i=i+1) bios[i]=0;
  $readmemh("../sim/smoke_bios.hex",bios);
  if($test$plusargs("VCD")) begin $dumpfile("gba_smoke.vcd"); $dumpvars(0,tb_gba_smoke); end
  repeat(8) @(posedge clk);
  for(i=0;i<4096;i=i+1) begin
   bios_wraddr<=i[11:0]; bios_wrdata<=bios[i]; bios_wr<=1; @(posedge clk);
  end
  bios_wr<=0; repeat(8) @(posedge clk); reset_n<=1;
 end
 always @(posedge clk) if(reset_n) begin
  cycles<=cycles+1;
  if(pixel_we && pixel_addr==0 && pixel_data[5:0]==6'h3f) begin
   $display("PASS: ARM BIOS executed and PPU emitted red pixel after %0d cycles",cycles); $finish;
  end
  if(cycles==20000000) begin
   $display("FAIL timeout pc=%08x pixel=%05x addr=%0d",debug_cpu_pc,pixel_data,pixel_addr); $fatal(1);
  end
 end
endmodule
`default_nettype wire
