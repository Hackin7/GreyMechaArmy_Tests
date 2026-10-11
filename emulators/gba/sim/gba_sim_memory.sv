`default_nettype none
module gba_sim_memory (
 input wire clk, input wire rom_read, input wire [24:0] rom_addr,
 output reg rom_done, output reg [31:0] rom_data,rom_second_data,
 input wire [31:0] ext_write_data, output reg [31:0] ext_read_data,
 input wire [25:0] ext_addr, input wire ext_read_not_write,ext_request,
 output reg ext_done
);
 reg [31:0] gamepak [0:8388607];
 reg [31:0] external [0:196607];
 reg [1023:0] rom_hex;
 initial begin
  rom_done=0; rom_data=0; rom_second_data=0; ext_done=0; ext_read_data=0;
  if ($value$plusargs("ROM_HEX=%s",rom_hex)) $readmemh(rom_hex,gamepak);
 end
 always @(posedge clk) begin
  rom_done<=0; ext_done<=0;
  if (rom_read) begin
   rom_data<=gamepak[rom_addr[22:0]];
   rom_second_data<=gamepak[rom_addr[22:0]+1'b1]; rom_done<=1;
  end
  if (ext_request) begin
   if (ext_read_not_write) ext_read_data<=external[ext_addr[17:0]];
   else external[ext_addr[17:0]]<=ext_write_data;
   ext_done<=1;
  end
 end
endmodule
`default_nettype wire

