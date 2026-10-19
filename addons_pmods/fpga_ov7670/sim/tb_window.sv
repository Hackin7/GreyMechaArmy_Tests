`timescale 1ns/1ps
module tb_window #(parameter SWAP=0);
    reg clk=0;always #5 clk=~clk;
    reg resetn=0,frame_available=0;
    wire [15:0] pixel_index;
    reg [15:0] q0,q1,q2,pixel_data;
    wire oled_scl,oled_sda,oled_dc,oled_cs,oled_rst;
    wire init_done,streaming,frame_start,frame_done;
    reg enabled=0;
    reg [6:0] offset=16;
    wire [15:0] corrected;
    integer images=0,clear_pixels=0,bits=0,pixels=0,command_bytes=0,window_bytes=0;
    integer x,y,r,g,b;
    reg [15:0] shift=0,expected,source;
    reg [7:0] byte_shift=0;
    reg [7:0] last_command=0;
    reg [7:0] window_data[0:7];
    camera_panel #(.CLK_HZ(1000),.SWAP_RB(SWAP)) dut(.*);
    rgb_offset correction(.pixel(q2),.enabled(enabled),.offset(offset),.corrected(corrected));
    function [15:0] pattern(input integer address);pattern=16'hffff^(address*17);endfunction
    always @(posedge clk) begin
        q0<=pattern(pixel_index);q1<=q0;q2<=q1;pixel_data<=corrected;
    end
    always @(posedge frame_start) begin
        if(streaming) $fatal(1,"Unsafe start");
        enabled=images==1;
    end
    // Decode the actual wire: byte commands and data, initial clear, images.
    always @(posedge oled_scl) if(!oled_cs) begin
        if(dut.state==1 || streaming) begin
            if(!oled_dc) $fatal(1,"Pixel DC low");
            shift={shift[14:0],oled_sda};bits=bits+1;
            if(bits==16) begin
                if(dut.state==1) begin
                    if(shift!=0) $fatal(1,"Nonblack initial clear");clear_pixels=clear_pixels+1;
                end else begin
                    source=pattern(pixels);expected=source;
                    if(enabled) begin
                        r={source[15:11],source[15:13]};g={source[10:5],source[10:9]};b={source[4:0],source[4:2]};
                        r=r>16?r-16:0;g=g>16?g-16:0;b=b>16?b-16:0;
                        expected=((r>>3)<<11)|((g>>2)<<5)|(b>>3);
                    end
                    if(SWAP) expected={expected[4:0],expected[10:5],expected[15:11]};
                    if(shift!==expected) $fatal(1,"Image %d pixel %d got %h expected %h",images,pixels,shift,expected);
                    pixels=pixels+1;
                end
                bits=0;
            end
        end else begin
            byte_shift={byte_shift[6:0],oled_sda};bits=bits+1;
            if(bits==8) begin
                if(dut.state!=0) begin
                    if(!oled_dc) begin last_command=byte_shift;command_bytes=command_bytes+1;end
                    else if(last_command==8'h2a || last_command==8'h2b) begin
                        window_data[window_bytes]=byte_shift;window_bytes=window_bytes+1;
                    end
                end
                bits=0;
            end
        end
    end
    always @(posedge frame_done) begin
        #1; // Allow combinational pin arbitration to settle after the shifter.
        if(pixels!=19200 || bits!=0 || !oled_cs)
            $fatal(1,"Wrong image length/boundary: pixels=%d bits=%d CS=%b",pixels,bits,oled_cs);
        images=images+1;pixels=0;
        if(images==2) begin
            if(clear_pixels!=57600 || window_bytes!=8 || command_bytes!=4) $fatal(1,"Clear/window count");
            if({window_data[0],window_data[1],window_data[2],window_data[3]}!==32'h002800c7 ||
               {window_data[4],window_data[5],window_data[6],window_data[7]}!==32'h003c00b3)
                $fatal(1,"Incorrect centered address window");
            $display("PASS window: black clear, centered bounds, 2 complete image transfers, correction, endpoints");$finish;
        end
    end
    initial begin
        force dut.initializer.rom_pause_r=1;
        repeat(5) @(negedge clk);resetn=1;
        wait(dut.init_ready);force dut.initializer.init_idx=0;
        wait(init_done);frame_available=1;
    end
    initial begin #100000000;$fatal(1,"Timeout");end
endmodule
