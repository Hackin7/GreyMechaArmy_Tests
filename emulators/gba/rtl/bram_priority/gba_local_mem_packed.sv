// Pack eight logical 32-bit words into seven 36-bit EBR words and a
// four-bit spill word. This uses the EBR parity bits without division:
// The theoretical minimum is 49 main EBRs + one spill EBR. Current Yosys
// maps the main array to 50 EBRs in 18-bit mode: 51 total, five spare.
// Read/modify/write preserves adjacent words and independent byte masks.
module gba_local_mem_packed(
    input wire clk,reset,
    input wire core_req,core_read,input wire [25:0] core_addr,
    input wire [31:0] core_data,output reg core_done,output reg [31:0] core_q,
    input wire video_req,video_read,input wire [13:0] video_addr,
    input wire [31:0] video_data,input wire [3:0] video_be,
    output reg video_done,output reg [31:0] video_q,
    input wire host_req,host_read,input wire [22:0] host_addr,
    input wire [31:0] host_data,input wire [3:0] host_be,
    output reg host_done,output reg [31:0] host_q
);
    (* ram_style="block" *) reg [35:0] main[0:25087];
    (* ram_style="block" *) reg [3:0] spill[0:4095];
    reg [14:0] pa,pb;reg [11:0] sa;reg [35:0] qa,qb,da,db,physical_q;reg [3:0] sq,sd;
    reg [3:0] state;reg [1:0] owner,turn;reg read_op,last_word;
    reg [5:0] offset;reg [31:0] held_data;reg [3:0] held_be;
    reg [2:0] pending;reg [14:0] addresses[0:2];
    reg [31:0] values[0:2];reg [3:0] masks[0:2];reg reads[0:2];
    localparam IDLE=0,READ1=1,CAPTURE1=2,WRITE=3,READ2=4,CAPTURE2=5,FINAL=6,WRITE2=7;
    wire [1:0] next=turn==2 ? 0:turn+1'b1;
    wire [1:0] previous=turn==0 ? 2:turn-1'b1;
    wire [1:0] selected=pending[turn] ? turn:pending[next] ? next:previous;
    wire [14:0] logical_addr=addresses[selected];
    wire [11:0] group_addr=logical_addr[14:3];
    wire [14:0] group_base={group_addr,3'b000}-{3'b000,group_addr};
    wire [14:0] first=group_base+(logical_addr[2:0]==0 ? 3'd0:logical_addr[2:0]-1'b1);
    wire [35:0] second=last_word ? {32'd0,sq}:qb;
    wire [71:0] pair={second,qa};
    wire [71:0] shifted=pair>>offset;
    wire [31:0] byte_mask={{8{held_be[3]}},{8{held_be[2]}},{8{held_be[1]}},{8{held_be[0]}}};
    wire [71:0] mask={40'd0,byte_mask}<<offset;
    wire [71:0] replacement={40'd0,held_data}<<offset;
    wire [71:0] merged=(pair&~mask)|(replacement&mask);
    // A single full-width write port and read port allow native 36-bit PDP
    // mode. True dual-port 36-bit inference would waste additional EBRs.
    wire [14:0] read_address=(state==READ2||state==CAPTURE2) ? pb:pa;
    wire [14:0] write_address=state==WRITE2 ? pb:pa;
    wire [35:0] write_data=state==WRITE2 ? db:da;
    wire write_enable=(state==WRITE&&mask[35:0]!=0)||state==WRITE2;
    always @(posedge clk)begin
        physical_q<=main[read_address];sq<=spill[sa];
        if(write_enable)main[write_address]<=write_data;
        if(state==WRITE&&last_word&&mask[39:36]!=0)spill[sa]<=sd;
    end
    task finish_request(input [31:0] value);
        begin
            case(owner)
              0:begin core_done<=1;core_q<=value;end
              1:begin video_done<=1;video_q<=value;end
              2:begin host_done<=1;host_q<=value;end
            endcase
            state<=IDLE;
        end
    endtask
    always @(posedge clk)begin
        core_done<=0;video_done<=0;host_done<=0;
        if(reset)begin state<=IDLE;pending<=0;turn<=0;pa<=0;pb<=0;sa<=0;end
        else begin
            case(state)
              IDLE:if(pending!=0)begin
                  owner<=selected;turn<=selected==2 ? 0:selected+1'b1;pending[selected]<=0;
                  read_op<=reads[selected];held_data<=values[selected];held_be<=masks[selected];
                  pa<=first;pb<=logical_addr[2:0]==7 ? first:first+1'b1;sa<=group_addr;
                  last_word<=logical_addr[2:0]==7;
                  offset<=logical_addr[2:0]==0 ? 0:36-{logical_addr[2:0],2'b00};
                  state<=READ1;
              end
              READ1:state<=CAPTURE1;
              CAPTURE1:begin
                  qa<=physical_q;
                  if(last_word||offset==0)begin qb<=0;state<=FINAL;end
                  else state<=READ2;
              end
              READ2:state<=CAPTURE2;
              CAPTURE2:begin qb<=physical_q;state<=FINAL;end
              FINAL:if(read_op)finish_request(shifted[31:0]);
                  else begin da<=merged[35:0];db<=merged[71:36];sd<=merged[39:36];state<=WRITE;end
              WRITE:if(last_word||mask[71:36]==0)finish_request(32'd0);else state<=WRITE2;
              WRITE2:finish_request(32'd0);
            endcase
            if(core_req)begin
                pending[0]<=1;addresses[0]<=core_addr<26'h12000 ? 15'd4096+{2'd0,core_addr[12:0]}:{3'd0,core_addr[11:0]};
                values[0]<=core_data;masks[0]<=15;reads[0]<=core_read;
            end
            if(video_req)begin pending[1]<=1;addresses[1]<=15'd12288+video_addr;values[1]<=video_data;masks[1]<=video_be;reads[1]<=video_read;end
            if(host_req)begin
                pending[2]<=1;
                if(host_addr>=23'h100000)addresses[2]<=15'd12288+host_addr[15:2];
                else if(host_addr<23'h48000)addresses[2]<=15'd4096+host_addr[14:2];
                else addresses[2]<={3'd0,host_addr[13:2]};
                values[2]<=host_data;masks[2]<=host_be;reads[2]<=host_read;
            end
        end
    end
endmodule
