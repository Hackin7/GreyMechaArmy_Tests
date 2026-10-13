// One queued request per graphics client. Each owns a disjoint PSRAM range.
// Round-robin service prevents a palette fetch starving a line-buffer write.
module gba_scratch_arbiter #(parameter N=10)(
 input wire clk,reset,input wire [N-1:0] req,read,
 input wire [N*23-1:0] addr,input wire [N*32-1:0] wdata,
 input wire [N*4-1:0] be,output reg [N-1:0] done,
 output reg [31:0] rdata,output reg mem_req,mem_read,
 output reg [22:0] mem_addr,output reg [31:0] mem_wdata,
 output reg [3:0] mem_be,input wire mem_done,input wire [31:0] mem_rdata
);
 reg [N-1:0] pending;
 // Clients hold their request attributes until done, avoiding a RAM queue.
 localparam INDEX_BITS=$clog2(N);
 reg [INDEX_BITS-1:0] owner,chosen;
 reg [N-1:0] priority_mask;
 wire [N-1:0] masked_pending=pending&priority_mask;
 wire [N-1:0] eligible=(|masked_pending)?masked_pending:pending;
 integer i;reg busy,found;
 always @(posedge clk) begin
  mem_req<=0;done<=0;
  if(reset)begin pending<=0;busy<=0;priority_mask<={N{1'b1}};owner<=0;rdata<=0;end
  else begin
   for(i=0;i<N;i=i+1)if(req[i])begin
    pending[i]<=1;
   end
   if(busy)begin
    if(mem_done)begin done[owner]<=1;rdata<=mem_rdata;busy<=0;end
   end else begin
    chosen=0;found=0;
    for(i=N-1;i>=0;i=i-1)begin
     if(eligible[i])begin chosen=i;found=1;end
    end
    if(found)begin
     owner<=chosen;
     for(i=0;i<N;i=i+1)priority_mask[i]<=i>chosen;
     pending[chosen]<=0;mem_req<=1;busy<=1;
     mem_addr<=addr[chosen*23+:23];mem_wdata<=wdata[chosen*32+:32];
     mem_read<=read[chosen];mem_be<=be[chosen*4+:4];
    end
   end
  end
 end
endmodule
