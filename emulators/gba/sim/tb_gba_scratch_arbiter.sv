`timescale 1ns/1ps
module tb_gba_scratch_arbiter;
 localparam N=14;
 reg clk=0,reset=1;always #5 clk=~clk;
 reg [N-1:0] req=0,read=0;reg [N*23-1:0] addr=0;
 reg [N*32-1:0] data=0;reg [N*4-1:0] be=0;
 wire [N-1:0] done;wire [31:0] q;wire mr,mread;
 wire [22:0] ma;wire [31:0] md;wire [3:0] mb;
 reg complete=0;reg [31:0] mq=0;
 gba_scratch_arbiter #(.N(N)) dut(clk,reset,req,read,addr,data,be,done,q,mr,mread,ma,md,mb,complete,mq);
 integer countdown=0,held,round,i,received;reg [N-1:0] seen=0;
 integer reference_next=0,expected_client,j,c;reg check_grant;
 reg [N-1:0] batch;integer total;
 // Check the actual RTL grant against the previous rotating-index rule.
 always @(negedge clk)begin
  check_grant=0;expected_client=-1;
  if(reset)reference_next=0;
  else if(!dut.busy)begin
   for(j=0;j<N;j=j+1)begin
    c=reference_next+j;if(c>=N)c=c-N;
    if(expected_client<0&&dut.pending[c])expected_client=c;
   end
   check_grant=expected_client>=0;
  end
 end
 always @(posedge clk)begin
  #1;
  if(!reset&&check_grant)begin
   if(!mr||ma!==addr[expected_client*23+:23])$fatal(1,"round-robin grant changed");
   reference_next=expected_client==N-1?0:expected_client+1;
  end
 end
 always @(posedge clk)begin
  complete<=0;
  if(mr)begin
   if(countdown!=0)$fatal(1,"overlapping physical requests");
   held=ma;countdown=3+(ma%7);
   if(md!==32'h12340000+ma||mb!==ma%16||mread!==ma%2)
    $fatal(1,"request attributes changed while queued");
  end else if(countdown>0)begin
   countdown=countdown-1;
   if(countdown==0)begin mq<=32'hbeef0000+held;complete<=1;end
  end
 end
 initial begin
  repeat(4)@(negedge clk);reset=0;
  for(round=0;round<32;round=round+1)begin
   for(i=0;i<N;i=i+1)begin
    addr[i*23+:23]=i+round*16;data[i*32+:32]=32'h12340000+i+round*16;
    be[i*4+:4]=i%16;read[i]=i%2;
   end
   batch=round<2?{N{1'b1}}:((round*137)^14'h2a5b);
   total=0;for(i=0;i<N;i=i+1)if(batch[i])total=total+1;
   req=batch;@(negedge clk);req=0;seen=0;received=0;
   while(received<total)begin
    @(negedge clk);
    for(i=0;i<N;i=i+1)if(done[i])begin
     if(seen[i])$fatal(1,"duplicate completion");
     if(q!==32'hbeef0000+i+round*16)$fatal(1,"wrong client's read data");
     seen[i]=1;received=received+1;
    end
   end
   repeat(3)@(negedge clk);
  end
  $display("PASS scratch arbiter: simultaneous clients, attributes, byte masks, fair completion");$finish;
 end
 initial begin #1000000;$fatal(1,"starved client");end
endmodule
