`timescale 1ns/1ps
module tb_display;
    reg clk=0; always #5 clk=~clk;
    reg resetn=0,enable=0,frame_valid=0,enabled=0;
    reg [6:0] offset=16;
    wire [15:0] pixel_index,pixel_data;
    wire [14:0] ram_address;
    reg [15:0] ram_data,ram_q,ram_bank_q;
    wire sclk,mosi,cs,dc,frame_done;
    integer bit_count=0,received=0,frame_number=0,x,y,a,r,g,b;
    reg [15:0] shift=0,expected,source;
    camera_viewport viewport(.*);
    oled_stream stream(.*);
    function [15:0] pattern(input integer address);
        pattern=16'hffff ^ (address*17);
    endfunction
    always @(posedge clk) begin
        ram_q<=pattern(ram_address); ram_bank_q<=ram_q; ram_data<=ram_bank_q;
    end
    always @(posedge sclk) begin
        if(cs || !dc) $fatal(1,"SPI framing");
        shift={shift[14:0],mosi}; bit_count=bit_count+1;
        if(bit_count==16) begin
            x=received%240; y=received/240; expected=0;
            if(frame_number==0 && x>=40 && x<200 && y>=60 && y<180)
                expected=x<80 ? 16'hf800:x<120 ? 16'h07e0:x<160 ? 16'h001f:16'hffff;
            if(frame_number>0 && x>=40 && x<200 && y>=60 && y<180) begin
                a=(y-60)*160+x-40; source=pattern(a); expected=source;
                if(frame_number==2) begin
                    r={source[15:11],source[15:13]};
                    g={source[10:5],source[10:9]}; b={source[4:0],source[4:2]};
                    r=r>16?r-16:0;g=g>16?g-16:0;b=b>16?b-16:0;
                    expected=((r>>3)<<11)|((g>>2)<<5)|(b>>3);
                end
            end
            if(shift !== expected)
                $fatal(1,"Frame %0d pixel %0d (%0d,%0d) expected %h got %h",frame_number,received,x,y,expected,shift);
            received=received+1; bit_count=0;
        end
    end
    initial begin
        repeat(5) @(negedge clk); resetn=1;
        for(frame_number=0;frame_number<3;frame_number=frame_number+1) begin
            frame_valid=frame_number!=0; enabled=frame_number==2;
            repeat(12) @(negedge clk); received=0; enable=1;
            wait(frame_done); @(negedge clk);
            if(received!=57600 || bit_count!=0 || !cs)
                $fatal(1,"Frame length: %0d pixels, %0d partial bits, CS=%b",received,bit_count,cs);
            enable=0; repeat(5) @(negedge clk);
        end
        $display("PASS display: 3 decoded SPI frames, viewport, borders, correction and endpoints"); $finish;
    end
    initial begin #100000000; $fatal(1,"Timeout"); end
endmodule
