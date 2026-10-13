`timescale 1ns/1ps
module tb_gba_local_mem;
 reg clk=0;always #25 clk=~clk;
 reg reset=1,cr=0,vr=0,hr=0,cread=1,vread=1,hread=1;
 reg [25:0] ca;reg [13:0] va;reg [22:0] ha;
 reg [31:0] cw,vw,hw;reg [3:0] vb=15,hb=15;
 wire cd,vd,hd;wire [31:0] cq,vq,hq;
 gba_local_mem dut(.clk(clk),.reset(reset),.core_req(cr),.core_read(cread),.core_addr(ca),.core_data(cw),.core_done(cd),.core_q(cq),
 .video_req(vr),.video_read(vread),.video_addr(va),.video_data(vw),.video_be(vb),.video_done(vd),.video_q(vq),
 .host_req(hr),.host_read(hread),.host_addr(ha),.host_data(hw),.host_be(hb),.host_done(hd),.host_q(hq));
 reg step=1,done=0;reg [31:0] data;wire pending;wire [31:0] held;
 gba_step_response response(.clk(clk),.reset(reset),.step(step),.done(done),.data(data),.pending(pending),.held(held));
 task host(input bit rd,input [22:0] addr,input [31:0] value,input [3:0] mask);
 begin @(negedge clk);hr=1;hread=rd;ha=addr;hw=value;hb=mask;
 @(negedge clk);hr=0;wait(hd);@(negedge clk);end endtask
 task core(input [25:0] addr,input [31:0] expected);
 begin @(negedge clk);cr=1;ca=addr;cread=1;@(negedge clk);cr=0;
 wait(cd);@(negedge clk);if(cq!==expected)$fatal(1,"core %h got %h expected %h",addr,cq,expected);end endtask
 task video(input [13:0] addr,input bit rd,input [31:0] value,input [3:0] mask);
 begin @(negedge clk);vr=1;va=addr;vread=rd;vw=value;vb=mask;@(negedge clk);vr=0;
 wait(vd);@(negedge clk);if(rd&&vq!==value)$fatal(1,"VRAM %h got %h expected %h",addr,vq,value);end endtask
 integer i,mask,word_index;reg [31:0] expected;reg [2:0] completed;
 initial begin
 repeat(4)@(negedge clk);reset=0;
 // Exercise every physical word and the loader-to-core address mapping.
 for(i=0;i<4096;i=i+1)host(0,23'h48000+i*4,32'hb1050000^i,15);
 for(i=0;i<4096;i=i+1)core(26'h12000+i,32'hb1050000^i);
 for(i=0;i<8192;i=i+1)host(0,23'h40000+i*4,32'haabb0000^i,15);
 for(i=0;i<8192;i=i+1)core(26'h10000+i,32'haabb0000^i);
 for(i=0;i<16384;i=i+1)host(0,23'h100000+i*4,32'hfeed0000^i,15);
 for(i=0;i<16384;i=i+1)video(i,1,32'hfeed0000^i,15);
 for(word_index=120;word_index<136;word_index=word_index+1)for(mask=0;mask<16;mask=mask+1)begin
 video(word_index,0,32'h11223344,15);video(word_index,0,32'haabbccdd,mask);
 expected=32'h11223344;for(i=0;i<4;i=i+1)if(mask[i])expected[i*8+:8]=32'haabbccdd>>(i*8);
 host(1,23'h100000+word_index*4,0,15);if(hq!==expected)$fatal(1,"host byte-mask %h word %h",mask,word_index);
 video(word_index-1,1,word_index==120 ? (32'hfeed0000^119):32'haabbccdd,15);
 video(word_index+1,1,32'hfeed0000^(word_index+1),15);
 end
 @(negedge clk);completed=0;cr=1;vr=1;hr=1;cread=1;vread=1;hread=1;
 ca=26'h12fff;va=16000;ha=23'h47ffc;
 @(negedge clk);cr=0;vr=0;hr=0;
 while(completed!=7)begin
 if(cd)begin completed[0]=1;if(cq!==(32'hb1050000^4095))$fatal(1,"parallel BIOS");end
 if(vd)begin completed[1]=1;if(vq!==(32'hfeed0000^16000))$fatal(1,"parallel VRAM");end
 if(hd)begin completed[2]=1;if(hq!==(32'haabb0000^8191))$fatal(1,"parallel host");end
 @(negedge clk);
 end
 @(posedge clk);step=0;done=1;data=32'h12345678;
 @(posedge clk);done=0;repeat(20)@(posedge clk);
 if(!pending||held!==32'h12345678)$fatal(1,"response lost while stopped");
 step=1;@(posedge clk);@(posedge clk);if(pending)$fatal(1,"response repeated");
 $display("PASS: all 28,672 local words, loader mappings, all VRAM byte masks, held responses");$finish;
 end
 initial begin #30000000;$fatal(1,"timeout");end
endmodule
