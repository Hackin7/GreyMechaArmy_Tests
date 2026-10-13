// Scanline payload lives in PSRAM. Small tags and one-word transport registers
// remain local. Stop guest clocks until each pixel write commits, and stop
// the panel clock on a read miss rather than losing a pixel on the SPI link.
module gba_lines_psram #(parameter SLOT_BITS=1)(
 input wire core_clk,core_reset,memory_tick,pixel_we,
 input wire [7:0] pixel_x,pixel_y,input wire [17:0] pixel_data,
 input wire mode_toggle,output wire video_ready,pixel_ready,
 output reg overflow,output reg [31:0] captured_frames,
 input wire panel_clk,panel_reset,input wire [7:0] rd_addr,
 output reg [15:0] rd_data,output wire line_ready,panel_data_ready,
 output wire [7:0] line_number,output wire line_fitted,input wire line_done,
 output reg write_req,output reg [22:0] write_addr,
 output reg [31:0] write_data,output reg [3:0] write_be,input wire write_done,
 output reg read_req,output reg [22:0] read_addr,
 input wire read_done,input wire [31:0] read_data
);
 localparam SLOTS=1<<SLOT_BITS;
 reg [8:0] tags[0:SLOTS-1];
 reg [SLOT_BITS:0] wp,rp,wg,rg;
 (* async_reg="true" *)reg [SLOT_BITS:0] r1,r2,w1,w2;
 reg fitted,seen_mode,writing,commit_line;
 reg [8:0] pending_tag;
 function [SLOT_BITS:0] binary;
  input [SLOT_BITS:0] gray;integer n;
  begin binary[SLOT_BITS]=gray[SLOT_BITS];
   for(n=SLOT_BITS-1;n>=0;n=n-1)binary[n]=binary[n+1]^gray[n];end
 endfunction
 wire [SLOT_BITS:0] used=wp-binary(r2);
 wire start_frame=pixel_x==0&&pixel_y==0;
 wire fit=start_frame?fitted^(mode_toggle!=seen_mode):fitted;
 wire keep_x=!fit||pixel_x%5!=2,keep_y=!fit||pixel_y%5!=2;
 wire [7:0] x=fit?pixel_x-(pixel_x+8'd2)/5:pixel_x;
 wire [7:0] y=fit?pixel_y-(pixel_y+8'd2)/5:pixel_y;
 wire [15:0] rgb={pixel_data[5:1],pixel_data[11:6],pixel_data[17:13]};
 assign video_ready=used<SLOTS-1;
 assign pixel_ready=!writing;
 assign line_ready=rg!=w2;
 assign line_number=tags[rp[SLOT_BITS-1:0]][7:0];
 assign line_fitted=tags[rp[SLOT_BITS-1:0]][8];
 always @(posedge core_clk)begin
  write_req<=0;r1<=rg;r2<=r1;
  if(core_reset)begin
   wp<=0;wg<=0;r1<=0;r2<=0;fitted<=1;seen_mode<=mode_toggle;
   overflow<=0;captured_frames<=0;writing<=0;commit_line<=0;
  end else begin
   if(writing&&write_done)begin
    writing<=0;
    if(commit_line)begin
     tags[wp[SLOT_BITS-1:0]]<=pending_tag;wp<=wp+1'b1;
     wg<=((wp+1'b1)>>1)^(wp+1'b1);commit_line<=0;
    end
   end
   if(pixel_we&&memory_tick)begin
    if(start_frame)begin fitted<=fit;seen_mode<=mode_toggle;end
    if(keep_y)begin
     if(used==SLOTS)overflow<=1;
     else if(keep_x)begin
      write_addr<=23'h200000+({{(23-SLOT_BITS){1'b0}},wp[SLOT_BITS-1:0]}<<9)+({15'd0,x[7:1],1'b0}<<1);
      write_data<={rgb,rgb};write_be<=x[0]?4'b1100:4'b0011;
      write_req<=1;writing<=1;
      if(pixel_x==239)begin commit_line<=1;pending_tag<={fit,y};end
     end
    end
    if(pixel_x==239&&pixel_y==159)captured_frames<=captured_frames+1'b1;
   end
  end
 end
 // Read coordinates are stable while the panel clock is stopped. Two-stage
 // synchronization of the published line pointer precedes any payload read.
 wire [SLOT_BITS+7:0] wanted={rp,rd_addr[7:1]};
 reg [SLOT_BITS+7:0] cache_tag,held_tag;
 reg [31:0] cache_data;reg valid,reading;
 wire hit=valid&&cache_tag==wanted;
 assign panel_data_ready=!line_ready||hit;
 always @(posedge core_clk)begin
  read_req<=0;
  if(core_reset)begin valid<=0;reading<=0;end
  else if(reading)begin
   if(read_done)begin cache_data<=read_data;cache_tag<=held_tag;valid<=1;reading<=0;end
  end else if(line_ready&&!hit)begin
   read_addr<=23'h200000+({{(23-SLOT_BITS-7){1'b0}},wanted[SLOT_BITS+6:0]}<<2);
   held_tag<=wanted;read_req<=1;reading<=1;
  end
  // Cache tags include the ring epoch, distinguishing a reused physical slot.
 end
 always @(posedge panel_clk)begin
  rd_data<=rd_addr[0]?cache_data[31:16]:cache_data[15:0];w1<=wg;w2<=w1;
  if(panel_reset)begin rp<=0;rg<=0;w1<=0;w2<=0;end
  else if(line_done&&line_ready)begin rp<=rp+1'b1;rg<=((rp+1'b1)>>1)^(rp+1'b1);end
 end
endmodule
