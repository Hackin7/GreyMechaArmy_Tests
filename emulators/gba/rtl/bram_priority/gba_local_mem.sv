// Full BIOS, IWRAM and lower VRAM: 8 + 16 + 32 ECP5 EBRs.
// Byte banking retains both ports' independent byte-write enables.
module gba_bram_bank #(parameter ADDR_BITS=12)(
    input wire clk,input wire a_en,a_read,input wire [ADDR_BITS-1:0] a_addr,
    input wire [31:0] a_data,input wire [3:0] a_be,output wire [31:0] a_q,
    input wire b_en,b_read,input wire [ADDR_BITS-1:0] b_addr,
    input wire [31:0] b_data,input wire [3:0] b_be,output wire [31:0] b_q
);
    genvar lane;
    generate for(lane=0;lane<4;lane=lane+1)begin: bytes
        (* ram_style="block" *) reg [7:0] mem[0:(1<<ADDR_BITS)-1];
        reg [7:0] qa,qb;
        always @(posedge clk)begin
            if(a_en)begin
                qa<=mem[a_addr];
                if(!a_read&&a_be[lane])mem[a_addr]<=a_data[lane*8+:8];
            end
            if(b_en)begin
                qb<=mem[b_addr];
                if(!b_read&&b_be[lane])mem[b_addr]<=b_data[lane*8+:8];
            end
        end
        assign a_q[lane*8+:8]=qa;assign b_q[lane*8+:8]=qb;
    end endgenerate
endmodule

module gba_local_mem(
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
    wire ci=core_addr>=26'h10000&&core_addr<26'h12000;
    wire cb=core_addr>=26'h12000&&core_addr<26'h13000;
    wire hi=host_addr>=23'h40000&&host_addr<23'h48000;
    wire hb=host_addr>=23'h48000&&host_addr<23'h4c000;
    wire hv=host_addr>=23'h100000&&host_addr<23'h110000;
    wire [31:0] bios_a,bios_b,iwram_a,iwram_b,vram_a,vram_b;
    gba_bram_bank #(.ADDR_BITS(12)) bios(.clk(clk),
        .a_en(core_req&&cb),.a_read(core_read),.a_addr(core_addr[11:0]),.a_data(core_data),.a_be(4'hf),.a_q(bios_a),
        .b_en(host_req&&hb),.b_read(host_read),.b_addr(host_addr[13:2]),.b_data(host_data),.b_be(host_be),.b_q(bios_b));
    gba_bram_bank #(.ADDR_BITS(13)) iwram(.clk(clk),
        .a_en(core_req&&ci),.a_read(core_read),.a_addr(core_addr[12:0]),.a_data(core_data),.a_be(4'hf),.a_q(iwram_a),
        .b_en(host_req&&hi),.b_read(host_read),.b_addr(host_addr[14:2]),.b_data(host_data),.b_be(host_be),.b_q(iwram_b));
    gba_bram_bank #(.ADDR_BITS(14)) lower_vram(.clk(clk),
        .a_en(video_req),.a_read(video_read),.a_addr(video_addr),.a_data(video_data),.a_be(video_be),.a_q(vram_a),
        .b_en(host_req&&hv),.b_read(host_read),.b_addr(host_addr[15:2]),.b_data(host_data),.b_be(host_be),.b_q(vram_b));
    reg cd,vd,hd,cb_d;reg [1:0] host_bank;
    always @(posedge clk)begin
        cd<=core_req;vd<=video_req;hd<=host_req;
        cb_d<=cb;host_bank<=hb?0:hi?1:2;
        core_done<=cd;video_done<=vd;host_done<=hd;
        if(cd)core_q<=cb_d?bios_a:iwram_a;
        if(vd)video_q<=vram_a;
        if(hd)host_q<=host_bank==0?bios_b:host_bank==1?iwram_b:vram_b;
        if(reset)begin cd<=0;vd<=0;hd<=0;core_done<=0;video_done<=0;host_done<=0;end
    end
endmodule

// Hold responses through a suspended emulator clock. Update on the falling
// edge, so the reply remains stable through the DCCA's next rising edge.
module gba_step_response(
    input wire clk,reset,step,done,input wire [31:0] data,
    output reg pending,output reg [31:0] held
);
    always @(negedge clk)begin
        if(reset)begin pending<=0;held<=0;end
        else begin
            if(step&&pending)pending<=0;
            if(done)begin pending<=1;held<=data;end
        end
    end
endmodule
