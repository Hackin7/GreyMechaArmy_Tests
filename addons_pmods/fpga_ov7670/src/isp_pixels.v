// Pull eight Sobel neighbors from an immutable framebuffer; no line RAM.
// Three-cycle synchronous read interface; two-result elastic queue.
module isp_pixels(
    input wire clk,resetn,start,stop,
    input wire enabled,input wire [2:0] mode,
    input wire [39:0] presets,input wire [15:0] value_q8,
    output reg [14:0] read_address,input wire [15:0] read_data,
    output wire valid,output wire [15:0] pixel,input wire take,
    output reg [31:0] stalls
);
    localparam IDLE=0,READ=1,DRAIN=2,POINT=3,MATH=4,ABS=5,SCALE=6,PACK=7,WRITE=8,
        DELTA=9,PRODUCT=10;
    reg [3:0] state;
    reg active;
    reg [14:0] position;
    reg [7:0] x,y;
    reg [3:0] issued;
    reg [2:0] pipe_valid;
    reg [2:0] tag0,tag1,tag2;
    reg [7:0] lum[0:7];
    reg [15:0] original,result;
    reg [7:0] r,g,b;
    reg [7:0] pivot;
    reg signed [9:0] dr,dg,db;
    reg signed [12:0] gx,gy;
    reg [12:0] magnitude;
    reg [31:0] scaled;
    reg signed [31:0] vr,vg,vb;
    reg [15:0] fifo[0:1];
    reg rd,wr;
    reg [1:0] count;
    wire pop=take && count!=0;
    wire push=state==WRITE && (count<2 || pop);
    wire sobel=enabled && mode==4;
    wire border=x==0 || x==159 || y==0 || y==119;
    wire issue=state==READ && issued<(sobel ? 8 : 1);
    assign valid=count!=0;
    assign pixel=fifo[rd];
    function [7:0] luma(input [15:0] p);
        integer rr,gg,bb;
        begin
            rr={p[15:11],p[15:13]};gg={p[10:5],p[10:9]};bb={p[4:0],p[4:2]};
            luma=(77*rr+150*gg+29*bb+128)>>8;
        end
    endfunction
    function [7:0] clamp(input signed [31:0] v);
        clamp=v<0 ? 0 : v>255 ? 255 : v[7:0];
    endfunction
    wire [7:0] qr,qg,qb;
    isp_gamma gamma(.clk(clk),.preset(presets[11:8]),.r(r),.g(g),.b(b),.qr(qr),.qg(qg),.qb(qb));
    wire signed [11:0] gain=$signed({1'b0,value_q8[10:0]});
    wire [12:0] ax=gx<0 ? -gx : gx;
    wire [12:0] ay=gy<0 ? -gy : gy;
    wire [7:0] cr=clamp(vr),cg=clamp(vg),cb=clamp(vb);
    wire [7:0] edge_value=scaled>261119 ? 255 : scaled[17:10];
    always @* begin
        read_address=position;
        if(sobel) case(issued)
            0:read_address=position-161;1:read_address=position-160;
            2:read_address=position-159;3:read_address=position-1;
            4:read_address=position+1;5:read_address=position+159;
            6:read_address=position+160;7:read_address=position+161;
            default:read_address=position;
        endcase
    end
    always @(posedge clk) begin
        if(!resetn || start) begin
            state<=IDLE;active<=start;position<=0;x<=0;y<=0;
            count<=0;rd<=0;wr<=0;pipe_valid<=0;issued<=0;
            if(!resetn) stalls<=0;
        end else begin
            if(stop) active<=0;
            if(take && !valid) stalls<=stalls+1'b1;
            case({push,pop})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:;
            endcase
            if(pop) rd<=!rd;
            if(push) begin fifo[wr]<=result;wr<=!wr;end
            pipe_valid<={pipe_valid[1:0],issue};
            tag0<=issued[2:0];tag1<=tag0;tag2<=tag1;
            if(pipe_valid[2]) begin
                if(sobel) begin
                    lum[tag2]<=luma(read_data);
                    if(tag2==7) state<=MATH;
                end else begin
                    original<=read_data;r<={read_data[15:11],read_data[15:13]};
                    g<={read_data[10:5],read_data[10:9]};b<={read_data[4:0],read_data[4:2]};
                    state<=POINT;
                end
            end
            case(state)
                IDLE: if(active && position<19200 && count<2) begin
                    issued<=0;
                    if(sobel && border) begin result<=0;state<=WRITE;end
                    else state<=READ;
                end
                READ: if(issue) begin
                    issued<=issued+1'b1;
                    if(issued==(sobel ? 7 : 0)) state<=DRAIN;
                end
                DRAIN:;
                POINT: begin
                    // Separate luma, channel deltas and DSP products for timing.
                    pivot<=mode==2 ? 128 : luma(original);state<=DELTA;
                end
                DELTA:begin
                    dr<=$signed({1'b0,r})-$signed({1'b0,pivot});
                    dg<=$signed({1'b0,g})-$signed({1'b0,pivot});
                    db<=$signed({1'b0,b})-$signed({1'b0,pivot});
                    state<=PRODUCT;
                end
                PRODUCT:begin
                    vr<=gain*dr+128;vg<=gain*dg+128;vb<=gain*db+128;
                    state<=SCALE;
                end
                MATH: begin
                    gx<=$signed({1'b0,lum[2]})+2*$signed({1'b0,lum[4]})+$signed({1'b0,lum[7]})-
                        $signed({1'b0,lum[0]})-2*$signed({1'b0,lum[3]})-$signed({1'b0,lum[5]});
                    gy<=$signed({1'b0,lum[5]})+2*$signed({1'b0,lum[6]})+$signed({1'b0,lum[7]})-
                        $signed({1'b0,lum[0]})-2*$signed({1'b0,lum[1]})-$signed({1'b0,lum[2]});
                    state<=ABS;
                end
                ABS: begin magnitude<=ax+ay;state<=SCALE;end
                SCALE: begin
                    if(sobel) scaled<=magnitude*value_q8+512;
                    else if(mode==0) begin
                        vr<=$signed({1'b0,r})-$signed({1'b0,value_q8[15:8]});
                        vg<=$signed({1'b0,g})-$signed({1'b0,value_q8[15:8]});
                        vb<=$signed({1'b0,b})-$signed({1'b0,value_q8[15:8]});
                    end else begin
                        vr<=$signed({1'b0,pivot})+(vr>>>8);
                        vg<=$signed({1'b0,pivot})+(vg>>>8);
                        vb<=$signed({1'b0,pivot})+(vb>>>8);
                    end
                    state<=PACK;
                end
                PACK: begin
                    if(!enabled) result<=original;
                    else if(sobel) result<={edge_value[7:3],edge_value[7:2],edge_value[7:3]};
                    else if(mode==1) result<={qr[7:3],qg[7:2],qb[7:3]};
                    else result<={cr[7:3],cg[7:2],cb[7:3]};
                    state<=WRITE;
                end
                WRITE: if(push) begin
                    position<=position+1'b1;
                    if(x==159) begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
                    state<=IDLE;
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
