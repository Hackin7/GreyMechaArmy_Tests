// GC9A01 waveform and synchronous prefetch follow the existing Game Boy
// line streamer. Stream the full 240x240 window: black borders are refreshed
// with every frame, so changing viewport leaves no stale pixels.
module gba_display #(
    parameter CLK_HZ=80000000, parameter SWAP_RB=1
)(
    input wire clk,resetn,
    input wire line_ready,line_fitted, input wire [7:0] line_number,
    output reg line_done, output reg [7:0] rd_addr,
    input wire [15:0] rd_data, output wire initialized,
    output reg [31:0] displayed_frames,
    output wire sclk,mosi,dc,cs_n,rst_n
);
    wire isclk,imosi,idc,ics,irst,ramwr;
    reg rearm,init_owner,started;
    reg ssclk,smosi,scs;
    reg [3:0] state,bit_count;
    reg [15:0] shift;
    reg [7:0] row,col;
    reg fitted,phase,next_active;
    wire [7:0] x0=fitted ? 24:0,y0=fitted ? 56:40;
    wire [7:0] width=fitted ? 192:240,height=fitted ? 128:160;
    wire active_row=row>=y0&&row<y0+height;
    wire [15:0] colour=SWAP_RB ? {rd_data[4:0],rd_data[10:5],rd_data[15:11]}:rd_data;
    gba_oled_init #(.CLK_HZ(CLK_HZ),.SPI_CLK_DIV(8'd4)) init(
        .clk(clk),.resetn(resetn),.rearm(rearm),.init_done(initialized),
        .ramwr_pulse(ramwr),.sclk(isclk),.mosi(imosi),.dc(idc),.cs(ics),.rst_n(irst));
    assign sclk=init_owner ? isclk:ssclk;
    assign mosi=init_owner ? imosi:smosi;
    assign dc=init_owner ? idc:1'b1;
    assign cs_n=init_owner ? ics:scs;
    assign rst_n=irst;
    always @(posedge clk) begin
        rearm<=0;line_done<=0;
        if(!resetn) begin
            init_owner<=1;started<=0;state<=0;row<=0;col<=0;
            fitted<=1;ssclk<=0;smosi<=0;scs<=1;rd_addr<=0;
            displayed_frames<=0;phase<=0;bit_count<=15;shift<=0;next_active<=0;
        end else begin
            if(!started&&initialized) begin started<=1;init_owner<=0;end
            if(ramwr) init_owner<=0;
            if(initialized&&!init_owner) case(state)
                0: if(line_ready) begin
                    if(line_number==0) begin fitted<=line_fitted;row<=0;state<=1;scs<=0;end
                    else begin line_done<=1;state<=6;end
                end
                1: begin
                    ssclk<=0;col<=0;rd_addr<=0;
                    if(!active_row || (line_ready&&line_number==row-y0)) state<=2;
                end
                2: state<=3;
                3: begin
                    shift<=(active_row&&x0==0) ? colour:16'd0;
                    smosi<=(active_row&&x0==0) ? colour[15]:1'b0;
                    bit_count<=15;phase<=0;state<=4;
                end
                4: if(!phase) begin ssclk<=1;phase<=1;end
                else begin
                    ssclk<=0;phase<=0;
                    if(bit_count==2) begin
                        next_active<=active_row && col+9'd1>=x0 && col+9'd1<x0+9'd240-(fitted ? 9'd48:9'd0);
                        if(col+9'd1>=x0 && col+9'd1<x0+{1'b0,width}) rd_addr<=col+8'd1-x0;
                    end
                    if(bit_count!=0) begin shift<={shift[14:0],1'b0};smosi<=shift[14];bit_count<=bit_count-1'b1;end
                    else if(col!=239) begin
                        col<=col+1'b1;bit_count<=15;
                        shift<=next_active ? colour:16'd0;smosi<=next_active ? colour[15]:1'b0;
                    end else begin
                        if(active_row) line_done<=1;
                        if(row==239) begin
                            scs<=1;displayed_frames<=displayed_frames+1'b1;
                            rearm<=1;init_owner<=1;state<=0;
                        end else begin row<=row+1'b1;state<=5;end
                    end
                end
                5: state<=1; // allow the FIFO read pointer to acknowledge
                6: state<=0; // discard each partial-frame row only once
                default: state<=0;
            endcase
        end
    end
endmodule
