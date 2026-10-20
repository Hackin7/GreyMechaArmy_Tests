// Own a camera bank from frame_start through final image bit; HUD is a separate window.
module isp_panel #(parameter CLK_HZ=50000000,SWAP_RB=1)(
    input wire clk,resetn,frame_available,
    output wire frame_start,frame_done,init_done,streaming,
    input wire enabled,input wire [2:0] mode,
    input wire [39:0] presets,input wire [15:0] value_q8,
    output wire [14:0] read_address,input wire [15:0] read_data,
    output wire oled_scl,oled_sda,oled_dc,oled_cs,oled_rst,
    output wire [31:0] pixel_wait_cycles
);
    wire init_ready,init_sck,init_mosi,init_dc,init_cs;
    oled_init #(.CLK_HZ(CLK_HZ)) initializer(.clk(clk),.resetn(resetn),
        .init_done(init_ready),.ramwr_pulse(),.rearm(1'b0),
        .sclk(init_sck),.mosi(init_mosi),.dc(init_dc),.cs(init_cs),.rst_n(oled_rst));
    localparam INIT=0,CLEAR=1,IDLE=2,SNAPSHOT=3,PREPARE=4,COMMAND=5,
        WAIT_COMMAND=6,HUD=7,IMAGE=8;
    reg [3:0] state;
    reg hud_window,hud_seen;
    reg [2:0] last_mode;
    reg last_enabled;
    reg [15:0] last_value;
    reg [3:0] command_index;
    reg command_start;
    wire command_busy,command_done,command_sck,command_mosi,command_dc,command_cs;
    function [7:0] command(input [3:0] index);
        case(index)
            0:command=8'h2a;1:command=0;2:command=40;3:command=0;4:command=199;
            5:command=8'h2b;6:command=0;7:command=hud_window ? 40 : 60;
            8:command=0;9:command=hud_window ? 51 : 179;default:command=8'h2c;
        endcase
    endfunction
    simple_spi_master commands(.clk(clk),.resetn(resetn),.clk_div(8'd4),
        .tx_data(command(command_index)),.start(command_start),.release_cs(1'b0),
        .keep_cs(1'b0),.idle_cs_n(1'b1),
        .dc_in(command_index!=0 && command_index!=5 && command_index!=10),.rst_n_in(1'b1),
        .busy(command_busy),.done(command_done),.sclk(command_sck),.mosi(command_mosi),
        .cs_n(command_cs),.dc(command_dc),.rst_n());
    wire clear_sck,clear_mosi,clear_cs,clear_dc,clear_done;
    oled_stream clear_screen(.clk(clk),.resetn(resetn),.enable(state==CLEAR),
        .pixel_index(),.pixel_data(16'd0),.sclk(clear_sck),.mosi(clear_mosi),
        .cs(clear_cs),.dc(clear_dc),.frame_done(clear_done));
    wire hud_sck,hud_mosi,hud_cs,hud_done,hud_take;
    wire [15:0] hud_pixel;
    isp_hud label_pixels(.clk(clk),.resetn(resetn),.start(state==PREPARE),.take(hud_take),
        .enabled(enabled),.mode(mode),.value_q8(value_q8),.pixel(hud_pixel));
    isp_spi #(.PIXELS(1920)) label_stream(.clk(clk),.resetn(resetn),.enable(state==HUD),
        .valid(1'b1),.pixel(hud_pixel),.take(hud_take),.sclk(hud_sck),.mosi(hud_mosi),
        .cs(hud_cs),.done(hud_done),.wait_cycles());
    wire valid,take,image_sck,image_mosi,image_cs,image_done;
    wire [15:0] pixel;
    isp_pixels pixels(.clk(clk),.resetn(resetn),.start(state==SNAPSHOT),.stop(image_done),
        .enabled(enabled),.mode(mode),.presets(presets),.value_q8(value_q8),
        .read_address(read_address),.read_data(read_data),.valid(valid),.pixel(pixel),.take(take),.stalls());
    wire [15:0] swapped=SWAP_RB ? {pixel[4:0],pixel[10:5],pixel[15:11]} : pixel;
    isp_spi image(.clk(clk),.resetn(resetn),.enable(state==IMAGE),.valid(valid),.pixel(swapped),
        .take(take),.sclk(image_sck),.mosi(image_mosi),.cs(image_cs),.done(image_done),
        .wait_cycles(pixel_wait_cycles));
    assign init_done=state!=INIT && state!=CLEAR;
    assign frame_start=state==IDLE && frame_available;
    assign frame_done=image_done;
    assign streaming=state==IMAGE;
    assign oled_scl=state==INIT ? init_sck : state==CLEAR ? clear_sck : state==HUD ? hud_sck : state==IMAGE ? image_sck : command_sck;
    assign oled_sda=state==INIT ? init_mosi : state==CLEAR ? clear_mosi : state==HUD ? hud_mosi : state==IMAGE ? image_mosi : command_mosi;
    assign oled_cs=state==INIT ? init_cs : state==CLEAR ? clear_cs : state==HUD ? hud_cs : state==IMAGE ? image_cs : command_cs;
    assign oled_dc=state==INIT ? init_dc : state==CLEAR ? clear_dc : state==HUD || state==IMAGE ? 1'b1 : command_dc;
    always @(posedge clk) begin
        command_start<=0;
        if(!resetn) begin state<=INIT;hud_seen<=0;command_index<=0;hud_window<=0;end
        else case(state)
            INIT:if(init_ready) state<=CLEAR;
            CLEAR:if(clear_done) state<=IDLE;
            IDLE:if(frame_available) state<=SNAPSHOT;
            SNAPSHOT:state<=PREPARE; // bank and control snapshots are now stable
            PREPARE:begin
                hud_window<=!hud_seen || mode!=last_mode || enabled!=last_enabled || value_q8!=last_value;
                last_mode<=mode;last_enabled<=enabled;last_value<=value_q8;
                command_index<=0;state<=COMMAND;
            end
            COMMAND:begin command_start<=1;state<=WAIT_COMMAND;end
            WAIT_COMMAND:if(command_done) begin
                if(command_index==10) state<=hud_window ? HUD : IMAGE;
                else begin command_index<=command_index+1'b1;state<=COMMAND;end
            end
            HUD:if(hud_done) begin hud_seen<=1;hud_window<=0;command_index<=0;state<=COMMAND;end
            IMAGE:if(image_done) state<=IDLE;
            default:state<=INIT;
        endcase
    end
endmodule
