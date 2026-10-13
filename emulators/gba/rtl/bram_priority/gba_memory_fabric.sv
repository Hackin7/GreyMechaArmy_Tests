// Existing loader map is unchanged. The three selected banks now live in
// local EBR. EWRAM/saves and upper VRAM remain in PSRAM.
module gba_memory_fabric(
    input wire clk,clk_ram,reset,step,
    input wire core_req,core_read,input wire [25:0] core_addr,input wire [31:0] core_wdata,
    output wire [31:0] core_rdata,output wire core_done,
    input wire host_req,host_read,input wire [22:0] host_addr,
    input wire [31:0] host_wdata,input wire [3:0] host_be,
    output wire [31:0] host_rdata,output wire host_done,
    input wire video_req,video_read,input wire [13:0] video_addr,
    input wire [31:0] video_wdata,input wire [3:0] video_be,
    output wire [31:0] video_rdata,output wire video_done,
    input wire upper_req,upper_read,input wire [12:0] upper_addr,
    input wire [31:0] upper_wdata,input wire [3:0] upper_be,
    output wire [31:0] upper_rdata,output wire upper_done,
    input wire [10:0] scratch_req,scratch_read,input wire [142:0] scratch_addr,
    input wire [351:0] scratch_wdata,input wire [43:0] scratch_be,
    output wire [31:0] scratch_rdata,output wire [10:0] scratch_done,
    input wire lcd_write_req,lcd_read_req,input wire [22:0] lcd_write_addr,lcd_read_addr,
    input wire [31:0] lcd_write_data,input wire [3:0] lcd_write_be,
    output wire lcd_write_done,lcd_read_done,output wire [31:0] lcd_read_data,
    output wire ready,output wire [23:0] device_id,output wire fault,idle,
    output wire cs_n,sck,input wire [3:0] dq_in,output wire [3:0] dq_out,dq_oe
);
    wire core_local=core_addr>=26'h10000&&core_addr<26'h13000;
    wire host_local=(host_addr>=23'h40000&&host_addr<23'h4c000)||
                    (host_addr>=23'h100000&&host_addr<23'h110000);
    wire ld_core,ld_host,ld_video,pd_core,pd_host;
    wire [31:0] lq_core,lq_host,lq_video,pq_core,pq_host;
    wire [321:0] graphics_addresses;
    assign graphics_addresses[276+:23]=lcd_write_addr;
    assign graphics_addresses[299+:23]=lcd_read_addr;
    assign graphics_addresses[22:0]=23'h110000+{8'd0,upper_addr,2'b00};
    genvar g;
    generate for(g=0;g<11;g=g+1)begin: scratch_regions
      assign graphics_addresses[(g+1)*23+:23]=23'h140000+g*4096+{8'd0,scratch_addr[g*13+:13],2'b00};
    end endgenerate
    wire gr_req,gr_read,gr_done;wire [22:0] gr_addr;
    wire [31:0] gr_wdata,gr_rdata;wire [3:0] gr_be;
    gba_scratch_arbiter #(.N(14)) graphics(.clk(clk),.reset(reset),
      .req({lcd_read_req,lcd_write_req,scratch_req,upper_req}),.read({1'b1,1'b0,scratch_read,upper_read}),
      .addr(graphics_addresses),.wdata({32'd0,lcd_write_data,scratch_wdata,upper_wdata}),.be({4'hf,lcd_write_be,scratch_be,upper_be}),
      .done({lcd_read_done,lcd_write_done,scratch_done,upper_done}),.rdata(scratch_rdata),
      .mem_req(gr_req),.mem_read(gr_read),.mem_addr(gr_addr),.mem_wdata(gr_wdata),
      .mem_be(gr_be),.mem_done(gr_done),.mem_rdata(gr_rdata));
    assign upper_rdata=scratch_rdata;
    assign lcd_read_data=scratch_rdata;
    gba_local_mem local_ram(.clk(clk),.reset(reset),
        .core_req(core_req&&step&&core_local),.core_read(core_read),.core_addr(core_addr),.core_data(core_wdata),.core_done(ld_core),.core_q(lq_core),
        .video_req(video_req&&step),.video_read(video_read),.video_addr(video_addr),.video_data(video_wdata),.video_be(video_be),.video_done(ld_video),.video_q(lq_video),
        .host_req(host_req&&host_local),.host_read(host_read),.host_addr(host_addr),.host_data(host_wdata),.host_be(host_be),.host_done(ld_host),.host_q(lq_host));
    gba_psram #(.ASYNC_CLOCK(1)) psram(.clk(clk),.clk_ram(clk_ram),.reset(reset),
        .core_req(core_req&&step&&!core_local),.core_read(core_read),.core_addr(core_addr),.core_wdata(core_wdata),.core_done(pd_core),.core_rdata(pq_core),
        .host_req(host_req&&!host_local),.host_read(host_read),.host_addr(host_addr),.host_wdata(host_wdata),.host_be(host_be),.host_done(pd_host),.host_rdata(pq_host),
        .video_req(gr_req),.video_read(gr_read),.video_addr(gr_addr),
        .video_wdata(gr_wdata),.video_be(gr_be),.video_done(gr_done),.video_rdata(gr_rdata),
        .ready(ready),.device_id(device_id),.fault(fault),.idle(idle),.cs_n(cs_n),.sck(sck),.dq_in(dq_in),.dq_out(dq_out),.dq_oe(dq_oe));
    gba_step_response core_reply(.clk(clk),.reset(reset),.step(step),
        .done(ld_core||pd_core),.data(ld_core?lq_core:pq_core),.pending(core_done),.held(core_rdata));
    gba_step_response video_reply(.clk(clk),.reset(reset),.step(step),
        .done(ld_video),.data(lq_video),.pending(video_done),.held(video_rdata));
    assign host_done=ld_host||pd_host;assign host_rdata=ld_host?lq_host:pq_host;
endmodule
