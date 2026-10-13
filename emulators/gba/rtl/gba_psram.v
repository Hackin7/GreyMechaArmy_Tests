// One SPI burst per complete word; masked writes retain individual byte lanes.
// Pulse requests are latched even
// when another client owns RAM. Each client has at most one outstanding word.
module gba_psram #(
    // At 20 MHz, divider one gives 10 MHz SCK. The 56-clock read-ID
    // must also finish within the chip's 8 us CE# refresh limit.
    parameter HALF_PERIOD=1, parameter READ_HALF_PERIOD=HALF_PERIOD,
    parameter READ_FALLING=0, parameter CS_GAP=4, parameter INIT_HALF_PERIOD=1,
    parameter POWERUP_CYCLES=20000, parameter ASYNC_CLOCK=0,
    // Priority-memory clients retain request attributes until completion.
    // Their existing registers can serve as the pending descriptor storage.
    parameter STABLE_CLIENTS=0
)(
    input wire clk, clk_ram, reset,
    input wire core_req, core_read, input wire [25:0] core_addr,
    input wire [31:0] core_wdata, output reg [31:0] core_rdata,
    output reg core_done,
    input wire host_req, host_read, input wire [22:0] host_addr,
    input wire [31:0] host_wdata, input wire [3:0] host_be,
    output reg [31:0] host_rdata, output reg host_done,
    input wire video_req, video_read, input wire [22:0] video_addr,
    input wire [31:0] video_wdata,input wire [3:0] video_be,
    output reg [31:0] video_rdata,output reg video_done,
    output wire ready, output wire [23:0] device_id,
    output reg fault, output wire idle,
    output wire cs_n, sck, input wire [3:0] dq_in,
    output wire [3:0] dq_out, dq_oe
);
    reg cp, hp, vp, read_op;
    reg [1:0] owner,last_owner,grant;
    wire [22:0] ca,ha,va;reg [22:0] address;
    wire cr,hr,vr;wire [31:0] cw,hw,vw;reg [31:0] word_data;
    wire [31:0] result;
    wire [3:0] hb,vb;reg [3:0] byte_enable;
    generate if(STABLE_CLIENTS)begin: live_descriptors
      assign ca={core_addr[20:0],2'b00};assign cr=core_read;assign cw=core_wdata;
      assign ha={host_addr[22:2],2'b00};assign hr=host_read;assign hw=host_wdata;assign hb=host_be;
      assign va={video_addr[22:2],2'b00};assign vr=video_read;assign vw=video_wdata;assign vb=video_be;
      // synthesis translate_off
      reg [55:0] check_core;reg [59:0] check_host,check_video;
      always @(posedge clk)if(!reset)begin
        if(cp&&{ca,cr,cw}!==check_core)$fatal(1,"Queued core request attributes changed");
        if(hp&&{ha,hr,hw,hb}!==check_host)$fatal(1,"Queued host request attributes changed");
        if(vp&&{va,vr,vw,vb}!==check_video)$fatal(1,"Queued video request attributes changed");
        if(core_req&&!cp)check_core<={ca,cr,cw};
        if(host_req&&!hp)check_host<={ha,hr,hw,hb};
        if(video_req&&!vp)check_video<={va,vr,vw,vb};
      end
      // synthesis translate_on
    end else begin: held_descriptors
      reg [22:0] caddr,haddr,vaddr;reg cread,hread,vread;
      reg [31:0] cword,hword,vword;reg [3:0] hmask,vmask;
      assign ca=caddr;assign cr=cread;assign cw=cword;
      assign ha=haddr;assign hr=hread;assign hw=hword;assign hb=hmask;
      assign va=vaddr;assign vr=vread;assign vw=vword;assign vb=vmask;
      always @(posedge clk)if(!reset)begin
        if(core_req&&!cp&&core_addr[25:21]==0)begin caddr<={core_addr[20:0],2'b00};cread<=core_read;cword<=core_wdata;end
        if(host_req&&!hp&&host_addr[1:0]==0)begin haddr<=host_addr;hread<=host_read;hword<=host_wdata;hmask<=host_be;end
        if(video_req&&!vp&&video_addr[1:0]==0)begin vaddr<=video_addr;vread<=video_read;vword<=video_wdata;vmask<=video_be;end
      end
    end endgenerate
    reg [1:0] index;
    reg [2:0] state;
    reg burst_req;
    wire burst_busy, burst_done;
    wire [7:0] burst_tx_index;
    wire full_word = read_op || byte_enable == 4'hf;
    wire [1:0] tx_lane = index + burst_tx_index[1:0];
    reg [17:0] timeout_count;
    assign idle = state == 0 && !cp && !hp && !vp;
    always @* begin
        // Rotate among core, host and video; no continuously active client
        // can starve either of the other two clients.
        case(last_owner)
            0: if(hp)grant=1;else if(vp)grant=2;else grant=0;
            1: if(vp)grant=2;else if(cp)grant=0;else grant=1;
            default: if(cp)grant=0;else if(hp)grant=1;else grant=2;
        endcase
    end
    gba_psram_link #(.HALF_PERIOD(HALF_PERIOD),.READ_HALF_PERIOD(READ_HALF_PERIOD),
        .READ_FALLING(READ_FALLING),.CS_GAP(CS_GAP),.INIT_HALF_PERIOD(INIT_HALF_PERIOD),
        .POWERUP_CYCLES(POWERUP_CYCLES),.ASYNC_CLOCK(ASYNC_CLOCK)) link (
        .clk(clk),.clk_ram(clk_ram),.reset(reset),.start(burst_req),.write(!read_op),
        .address({1'b0,address[22:2],index}),.length(full_word ? 9'd4 : 9'd1),
        .tx_index(burst_tx_index),.tx_data(word_data[tx_lane*8 +: 8]),
        .result(result),.ready(ready),.device_id(device_id),
        .dq_in(dq_in),.dq_out(dq_out),.dq_oe(dq_oe),
        .cs_n(cs_n),.sck(sck),.busy(burst_busy),.done(burst_done));
    always @(posedge clk) begin
        burst_req <= 0; core_done <= 0; host_done <= 0;video_done<=0;
        if (reset) begin
            cp<=0;hp<=0;vp<=0;state<=0;fault<=0;last_owner<=0;
            core_rdata<=0;host_rdata<=0;video_rdata<=0;timeout_count<=0;
            burst_req<=0;index<=0;address<=0;word_data<=0;
            read_op<=1;owner<=0;byte_enable<=0;
        end else begin
            if (core_req) begin
                if (cp || core_addr[25:21] != 0) fault<=1;
                else cp<=1;
            end
            if (host_req) begin
                if (hp || host_addr[1:0] != 0) fault<=1;
                else hp<=1;
            end
            if(video_req) begin
                if(vp || video_addr[1:0]!=0)fault<=1;
                else vp<=1;
            end
            if (state != 0) begin
                timeout_count<=timeout_count+1'b1;
                if (&timeout_count) fault<=1;
            end else timeout_count<=0;
            case (state)
                0: if (ready && !burst_busy && (cp || hp || vp)) begin
                    index<=0;state<=1;
                    owner<=grant;last_owner<=grant;
                    if(grant==2)begin
                        vp<=0;address<=va;read_op<=vr;word_data<=vw;byte_enable<=vb;
                    end else if (grant==1) begin
                        hp<=0;address<=ha;
                        read_op<=hr;word_data<=hw;byte_enable<=hb;
                    end else begin
                        cp<=0;address<=ca;
                        read_op<=cr;word_data<=cw;byte_enable<=4'hf;
                    end
                end
                1: if (!read_op && !byte_enable[index]) begin
                    if (index==3) state<=3; else index<=index+1'b1;
                end else if (!burst_busy) begin burst_req<=1;state<=2;end
                2: begin
                    if (burst_done) begin
                        if(full_word || index==3) state<=3;
                        else begin index<=index+1'b1;state<=1;end
                    end
                end
                3: begin
                    if(owner==2)begin video_rdata<=result;video_done<=1;end
                    else if(owner==1) begin host_rdata<=result;host_done<=1;end
                    else begin core_rdata<=result;core_done<=1;end
                    state<=0;
                end
                default: state<=0;
            endcase
        end
    end
endmodule

// Bundled-data request/acknowledge bridge. The arbiter holds address, length,
// write mode and word_data until the acknowledged transfer completes. The PHY
// holds result until the next request; two acknowledgement synchronizers give
// that bus time to settle before the core consumes it. tx_index is used only
// combinationally with the held word_data, entirely in the PHY domain.
module gba_psram_link #(
    parameter HALF_PERIOD=1, READ_HALF_PERIOD=HALF_PERIOD, READ_FALLING=0, CS_GAP=4,
              INIT_HALF_PERIOD=1, POWERUP_CYCLES=20000, ASYNC_CLOCK=0
)(
    input wire clk,clk_ram,reset,start,write,
    input wire [23:0] address,input wire [8:0] length,
    output wire [7:0] tx_index,input wire [7:0] tx_data,
    output reg [31:0] result,
    output wire ready,output wire [23:0] device_id,
    input wire [3:0] dq_in,output wire [3:0] dq_out,dq_oe,
    output wire cs_n,sck,busy,done
);
    wire phy_clk=ASYNC_CLOCK ? clk_ram : clk;
    wire phy_reset,phy_start,phy_busy,phy_done,phy_ready,rx_valid;
    wire [7:0] rx_index,rx_data;
    generate if(ASYNC_CLOCK) begin : bridge
        (* async_reg="true" *) reg [1:0] reset_release=0;
        always @(posedge clk_ram or posedge reset)
            if(reset)reset_release<=0;else reset_release<={reset_release[0],1'b1};
        assign phy_reset=!reset_release[1];
        reg request_toggle,request_seen,ack_toggle,ack_seen,inflight,start_phy;
        (* async_reg="true" *) reg [1:0] request_sync,ack_sync,ready_sync;
        assign phy_start=start_phy;
        assign busy=inflight;
        assign done=ack_sync[1]!=ack_seen;
        assign ready=ready_sync[1];
        always @(posedge clk) begin
            if(reset)begin
                request_toggle<=0;ack_seen<=0;inflight<=0;ack_sync<=0;ready_sync<=0;
            end else begin
                ack_sync<={ack_sync[0],ack_toggle};ready_sync<={ready_sync[0],phy_ready};
                ack_seen<=ack_sync[1];
                if(start)begin request_toggle<=!request_toggle;inflight<=1;end
                else if(done)inflight<=0;
            end
        end
        always @(posedge clk_ram) begin
            start_phy<=0;
            if(phy_reset)begin
                request_sync<=0;request_seen<=0;ack_toggle<=0;start_phy<=0;
            end else begin
                request_sync<={request_sync[0],request_toggle};
                if(request_sync[1]!=request_seen && !phy_busy)begin
                    request_seen<=request_sync[1];start_phy<=1;
                end
                if(phy_done)ack_toggle<=request_seen;
            end
        end
    end else begin : direct
        assign phy_reset=reset;assign phy_start=start;
        assign ready=phy_ready;assign busy=phy_busy;assign done=phy_done;
    end endgenerate
    wire init_cs,init_sck,burst_cs,burst_sck;
    wire [3:0] init_out,init_oe,burst_out,burst_oe;
    psram_spi #(.ENABLE_QPI(0),.INIT_HALF_PERIOD(INIT_HALF_PERIOD),
        .POWERUP_CYCLES(POWERUP_CYCLES)) chip(
        .clk(phy_clk),.reset(phy_reset),.request(1'b0),.operation(2'd0),
        .address(24'd0),.write_data(8'd0),.busy(),.ready(phy_ready),.done(),
        .qpi_mode(),.read_data(),.device_id(device_id),
        .cs_n(init_cs),.sck(init_sck),.dq_in(dq_in),.dq_out(init_out),.dq_oe(init_oe));
    spi_burst #(.HALF_PERIOD(HALF_PERIOD),.READ_HALF_PERIOD(READ_HALF_PERIOD),
        .READ_FALLING(READ_FALLING),.CS_GAP(CS_GAP),.FAST_READ(1)) burst(
        .clk(phy_clk),.reset(phy_reset),.start(phy_start),.write(write),
        .address(address),.length(length),.tx_index(tx_index),.tx_data(tx_data),
        .rx_valid(rx_valid),.rx_index(rx_index),.rx_data(rx_data),
        .dq_in(dq_in),.dq_out(burst_out),.dq_oe(burst_oe),
        .cs_n(burst_cs),.sck(burst_sck),.busy(phy_busy),.done(phy_done),
        .sck_pad(1'b0),.trace_index(5'd0),.trace_word());
    always @(posedge phy_clk)
        if(phy_reset || phy_start)result<=0;
        else if(rx_valid)result[rx_index[1:0]*8+:8]<=rx_data;
    assign cs_n=phy_ready ? burst_cs : init_cs;
    assign sck=phy_ready ? burst_sck : init_sck;
    assign dq_out=phy_ready ? burst_out : init_out;
    assign dq_oe=phy_ready ? burst_oe : init_oe;
endmodule
