`timescale 1ns/1ps
module tb_isp_panel;
    reg clk=0;always #5 clk=~clk;
    reg resetn=0,frame_available=0,enabled=1;
    reg [2:0] mode=0;
    reg [39:0] presets=40'h030a0a0604;
    reg [15:0] value_q8=4096;
    wire frame_start,frame_done,init_done,streaming;
    wire [14:0] read_address;
    reg [15:0] read_data,q0,q1;
    wire oled_scl,oled_sda,oled_dc,oled_cs,oled_rst;
    wire [31:0] pixel_wait_cycles;
    isp_panel #(.CLK_HZ(1000),.SWAP_RB(1)) dut(.*);
    reg [15:0] source[0:19199],expected[0:19199],hud_expected[0:1919];
    string dir,path;
    integer frames=0,pixels=0,hud_pixels=0,clear_pixels=0,huds=0;
    integer bits=0,command_bits=0,param_count=0;
    integer col0=0,col1=239,row0=0,row1=239;
    reg [15:0] shift=0;
    reg [7:0] opcode=8'h2c,byte_shift=0;
    reg [31:0] params=0;
    always @(posedge clk) begin q0<=source[read_address];q1<=q0;read_data<=q1;end
    always @(posedge frame_start) begin
        mode=frames<5 ? frames : 4;enabled=frames!=6;
        case(mode)
            0:value_q8=4096;1:value_q8=384;2,3:value_q8=320;4:value_q8=256;
        endcase
        path=$sformatf("%s/panel%0d.hex",dir,frames);$readmemh(path,expected);
        path=$sformatf("%s/hud%0d.hex",dir,frames);$readmemh(path,hud_expected);
    end
    reg [15:0] want;
    always @(posedge oled_scl) if(!oled_cs && dut.state!=0) begin
        if(dut.state==1 || dut.state==7 || streaming) begin
            if(!oled_dc) $fatal(1,"Pixel DC");
            shift={shift[14:0],oled_sda};bits=bits+1;
            if(bits==16) begin
                bits=0;
                if(dut.state==1) begin
                    if(shift!=0) $fatal(1,"Clear not black");clear_pixels=clear_pixels+1;
                end else if(dut.state==7) begin
                    if({col0[15:0],col1[15:0],row0[15:0],row1[15:0]}!==64'h002800c700280033)
                        $fatal(1,"HUD window");
                    if(shift!==hud_expected[hud_pixels]) $fatal(1,"HUD frame %0d pixel %0d got %h expected %h",frames,hud_pixels,shift,hud_expected[hud_pixels]);
                    hud_pixels=hud_pixels+1;
                end else begin
                    if({col0[15:0],col1[15:0],row0[15:0],row1[15:0]}!==64'h002800c7003c00b3)
                        $fatal(1,"Image window");
                    want=expected[pixels];want={want[4:0],want[10:5],want[15:11]};
                    if(shift!==want) $fatal(1,"SPI frame %0d mode %0d pixel %0d got %h expected %h",frames,mode,pixels,shift,want);
                    pixels=pixels+1;
                end
            end
        end else begin
            byte_shift={byte_shift[6:0],oled_sda};command_bits=command_bits+1;
            if(command_bits==8) begin
                command_bits=0;
                if(!oled_dc) begin opcode=byte_shift;param_count=0;params=0;end
                else if(opcode==8'h2a || opcode==8'h2b) begin
                    params={params[23:0],byte_shift};param_count=param_count+1;
                    if(param_count==4) begin
                        if(opcode==8'h2a) begin col0=params[31:16];col1=params[15:0];end
                        else begin row0=params[31:16];row1=params[15:0];end
                    end
                end
            end
        end
    end
    always @(posedge dut.hud_done) begin
        if(hud_pixels!=1920 || bits) $fatal(1,"HUD length");
        hud_pixels=0;huds=huds+1;
    end
    always @(posedge frame_done) begin
        #1;
        if(pixels!=19200 || bits || !oled_cs || pixel_wait_cycles!=0) $fatal(1,"Frame count/queue starvation");
        pixels=0;frames=frames+1;
        if(frames==7) begin
            if(huds!=6 || clear_pixels!=57600) $fatal(1,"HUD must update only for changed settings");
            $display("PASS ISP panel: seven full SPI images, all modes, exact HUD glyphs/values, bypass, bounds, color swap, no starvation");$finish;
        end
    end
    initial begin
        if(!$value$plusargs("VECTORS=%s",dir)) $fatal(1,"Vectors required");
        path={dir,"/panel_source.hex"};$readmemh(path,source);
        force dut.initializer.rom_pause_r=1;
        repeat(5) @(negedge clk);resetn=1;
        wait(dut.init_ready);force dut.initializer.init_idx=0;
        wait(init_done);frame_available=1;
    end
    initial begin #100000000;$fatal(1,"ISP panel timeout");end
endmodule
