// Configurable scanline FIFO; Gray pointers cross core and panel clocks.
// Reserve one slot for the renderer's in-flight line before backpressure.
module gba_lines #(parameter SLOT_BITS=2)(
    input wire core_clk,core_reset, input wire pixel_we,
    input wire [7:0] pixel_x,pixel_y, input wire [17:0] pixel_data,
    input wire mode_toggle, output wire video_ready, output reg overflow,
    output reg [31:0] captured_frames,
    input wire panel_clk,panel_reset, input wire [7:0] rd_addr,
    output reg [15:0] rd_data, output wire line_ready,
    output wire [7:0] line_number, output wire line_fitted,
    input wire line_done
);
    localparam SLOTS=1<<SLOT_BITS;
    reg [15:0] pixels[0:SLOTS*256-1];
    reg [8:0] tags[0:SLOTS-1];
    reg [SLOT_BITS:0] wp,rp,wg,rg;
    (* async_reg="true" *) reg [SLOT_BITS:0] r1,r2,w1,w2;
    reg fitted,seen_mode;
    function [SLOT_BITS:0] gray_to_binary;
        input [SLOT_BITS:0] value;integer bit_index;
        begin gray_to_binary[SLOT_BITS]=value[SLOT_BITS];
            for(bit_index=SLOT_BITS-1;bit_index>=0;bit_index=bit_index-1)
                gray_to_binary[bit_index]=gray_to_binary[bit_index+1]^value[bit_index];
        end
    endfunction
    wire [SLOT_BITS:0] rb=gray_to_binary(r2);
    wire [SLOT_BITS:0] used=wp-rb;
    wire frame_start=pixel_x==0 && pixel_y==0;
    wire selected_fit=frame_start  ?  fitted^(mode_toggle!=seen_mode) : fitted;
    wire keep_x=!selected_fit || pixel_x%5!=2;
    wire keep_y=!selected_fit || pixel_y%5!=2;
    wire [7:0] x=selected_fit  ?  pixel_x-(pixel_x+8'd2)/5 : pixel_x;
    wire [7:0] y=selected_fit  ?  pixel_y-(pixel_y+8'd2)/5 : pixel_y;
    wire [15:0] rgb565={pixel_data[5:1],pixel_data[11:6],pixel_data[17:13]};
    assign video_ready=used<SLOTS-1;
    assign line_ready=rg!=w2;
    assign line_number=tags[rp[SLOT_BITS-1:0]][7:0];
    assign line_fitted=tags[rp[SLOT_BITS-1:0]][8];
    always @(posedge core_clk) begin
        r1<=rg;r2<=r1;
        if(core_reset) begin wp<=0;wg<=0;r1<=0;r2<=0;fitted<=1;seen_mode<=mode_toggle;overflow<=0;captured_frames<=0;end
        else if(pixel_we) begin
            if(frame_start) begin fitted<=selected_fit;seen_mode<=mode_toggle;end
            if(keep_y) begin
                if(used==SLOTS) overflow<=1;
                else if(keep_x) pixels[{wp[SLOT_BITS-1:0],x}]<=rgb565;
                if(pixel_x==239 && used<SLOTS) begin
                    tags[wp[SLOT_BITS-1:0]]<={selected_fit,y};
                    wp<=wp+1'b1;wg<=((wp+1'b1)>>1)^(wp+1'b1);
                end
            end
            if(pixel_x==239&&pixel_y==159) captured_frames<=captured_frames+1'b1;
        end
    end
    always @(posedge panel_clk) begin
        rd_data<=pixels[{rp[SLOT_BITS-1:0],rd_addr}];
        w1<=wg;w2<=w1;
        if(panel_reset) begin rp<=0;rg<=0;w1<=0;w2<=0;end
        else if(line_done&&line_ready) begin rp<=rp+1'b1;rg<=((rp+1'b1)>>1)^(rp+1'b1);end
    end
endmodule
