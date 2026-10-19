// Clear all panel GRAM once, then update only columns 40..199, rows 60..179.
// frame_start reserves an immutable bank; frame_done releases it.
module camera_panel #(parameter CLK_HZ=50000000, SWAP_RB=0)(
    input wire clk,resetn,frame_available,
    input wire [15:0] pixel_data,
    output wire [15:0] pixel_index,
    output wire frame_start,frame_done,init_done,streaming,
    output wire oled_scl,oled_sda,oled_dc,oled_cs,oled_rst
);
    wire init_ready,unused_pulse,init_sck,init_mosi,init_dc,init_cs;
    oled_init #(.CLK_HZ(CLK_HZ)) initializer(.clk(clk),.resetn(resetn),
        .init_done(init_ready),.ramwr_pulse(unused_pulse),.rearm(1'b0),
        .sclk(init_sck),.mosi(init_mosi),.dc(init_dc),.cs(init_cs),.rst_n(oled_rst));
    localparam INIT=0,CLEAR=1,CMD=2,CMD_WAIT=3,IDLE=4,STREAM=5;
    reg [2:0] state;
    reg [3:0] command_index;
    reg command_start;
    wire command_busy,command_done,command_sck,command_mosi,command_dc,command_cs;
    function [7:0] command(input [3:0] index);
        case(index)
            0:command=8'h2a;1:command=0;2:command=40;3:command=0;4:command=199;
            5:command=8'h2b;6:command=0;7:command=60;8:command=0;9:command=179;
            default:command=8'h2c;
        endcase
    endfunction
    wire command_is_data=command_index!=0 && command_index!=5 && command_index!=10;
    simple_spi_master commands(.clk(clk),.resetn(resetn),.clk_div(8'd4),
        .tx_data(command(command_index)),.start(command_start),.release_cs(1'b0),
        .keep_cs(1'b0),.idle_cs_n(1'b1),.dc_in(command_is_data),.rst_n_in(1'b1),
        .busy(command_busy),.done(command_done),.sclk(command_sck),
        .mosi(command_mosi),.cs_n(command_cs),.dc(command_dc),.rst_n());
    wire clear_sck,clear_mosi,clear_cs,clear_dc,clear_done;
    wire [15:0] unused_index;
    oled_stream clear_screen(.clk(clk),.resetn(resetn),.enable(state==CLEAR),
        .pixel_index(unused_index),.pixel_data(16'd0),.sclk(clear_sck),
        .mosi(clear_mosi),.cs(clear_cs),.dc(clear_dc),.frame_done(clear_done));
    wire image_sck,image_mosi,image_cs,image_dc,image_done;
    wire [15:0] swapped=SWAP_RB ? {pixel_data[4:0],pixel_data[10:5],pixel_data[15:11]} : pixel_data;
    oled_stream #(.PIXELS(19200)) image(.clk(clk),.resetn(resetn),.enable(state==STREAM),
        .pixel_index(pixel_index),.pixel_data(swapped),.sclk(image_sck),
        .mosi(image_mosi),.cs(image_cs),.dc(image_dc),.frame_done(image_done));
    assign init_done=state!=INIT && state!=CLEAR;
    assign frame_start=state==IDLE && frame_available;
    assign frame_done=image_done;
    assign streaming=state==STREAM;
    assign oled_scl=state==INIT ? init_sck : state==CLEAR ? clear_sck : state==STREAM ? image_sck : command_sck;
    assign oled_sda=state==INIT ? init_mosi : state==CLEAR ? clear_mosi : state==STREAM ? image_mosi : command_mosi;
    assign oled_cs=state==INIT ? init_cs : state==CLEAR ? clear_cs : state==STREAM ? image_cs : command_cs;
    assign oled_dc=state==INIT ? init_dc : state==CLEAR ? clear_dc : state==STREAM ? image_dc : command_dc;
    always @(posedge clk) begin
        command_start<=0;
        if(!resetn) begin state<=INIT;command_index<=0;end
        else case(state)
            INIT: if(init_ready) state<=CLEAR;
            CLEAR: if(clear_done) begin command_index<=0;state<=CMD;end
            CMD: if(!command_busy) begin command_start<=1;state<=CMD_WAIT;end
            CMD_WAIT: if(command_done) begin
                if(command_index==9) state<=IDLE;
                else if(command_index==10) state<=STREAM;
                else begin command_index<=command_index+1'b1;state<=CMD;end
            end
            IDLE: if(frame_available) begin command_index<=10;state<=CMD;end
            STREAM: if(image_done) state<=IDLE;
            default:state<=INIT;
        endcase
    end
endmodule
