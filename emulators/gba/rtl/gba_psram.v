// Four single-byte SPI transactions per word. Pulse requests are latched even
// when another client owns RAM. Each client has at most one outstanding word.
module gba_psram #(
    parameter HALF_PERIOD=4, parameter POWERUP_CYCLES=20000
)(
    input wire clk, reset,
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
    reg [22:0] ca, ha, address;
    reg cr, hr;
    reg [31:0] cw, hw, word_data, result;
    reg [3:0] hb, byte_enable;
    reg [22:0] va;reg vr;reg [31:0] vw;reg [3:0] vb;
    reg [1:0] index;
    reg [2:0] state;
    reg byte_req;
    wire byte_busy, byte_done;
    wire [7:0] byte_data;
    wire unused_qpi;
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
    psram_spi #(.ENABLE_QPI(0),.INIT_HALF_PERIOD(HALF_PERIOD),
        .POWERUP_CYCLES(POWERUP_CYCLES)) chip (
        .clk(clk),.reset(reset),.request(byte_req),
        .operation(read_op  ?  2'd0 : 2'd1),
        .address({1'b0,address}+{22'd0,index}),
        .write_data(word_data[index*8 +: 8]),.busy(byte_busy),
        .ready(ready),.done(byte_done),.qpi_mode(unused_qpi),
        .read_data(byte_data),.device_id(device_id),
        .cs_n(cs_n),.sck(sck),.dq_in(dq_in),.dq_out(dq_out),.dq_oe(dq_oe));
    always @(posedge clk) begin
        byte_req <= 0; core_done <= 0; host_done <= 0;video_done<=0;
        if (reset) begin
            cp<=0;hp<=0;vp<=0;state<=0;fault<=0;last_owner<=0;
            core_rdata<=0;host_rdata<=0;video_rdata<=0;timeout_count<=0;
            byte_req<=0;index<=0;address<=0;word_data<=0;result<=0;
            read_op<=1;owner<=0;byte_enable<=0;
        end else begin
            if (core_req) begin
                if (cp || core_addr[25:21] != 0) fault<=1;
                else begin cp<=1;ca<={core_addr[20:0],2'b00};cr<=core_read;cw<=core_wdata;end
            end
            if (host_req) begin
                if (hp || host_addr[1:0] != 0) fault<=1;
                else begin hp<=1;ha<=host_addr;hr<=host_read;hw<=host_wdata;hb<=host_be;end
            end
            if(video_req) begin
                if(vp || video_addr[1:0]!=0)fault<=1;
                else begin vp<=1;va<=video_addr;vr<=video_read;vw<=video_wdata;vb<=video_be;end
            end
            if (state != 0) begin
                timeout_count<=timeout_count+1'b1;
                if (&timeout_count) fault<=1;
            end else timeout_count<=0;
            case (state)
                0: if (ready && !byte_busy && (cp || hp || vp)) begin
                    index<=0; result<=0; state<=1;
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
                end else if (!byte_busy) begin byte_req<=1;state<=2;end
                2: if (byte_done) begin
                    result[index*8 +: 8]<=byte_data;
                    if(index==3) state<=3;else begin index<=index+1'b1;state<=1;end
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
