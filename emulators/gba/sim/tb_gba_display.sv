`timescale 1ns/1ps
module tb_gba_display #(
    parameter real CORE_HALF_NS=25,
    parameter real PANEL_HALF_NS=6.25
);
    reg cc=0,pc=0,reset=1;
    always #(CORE_HALF_NS) cc=~cc;
    always #(PANEL_HALF_NS) pc=~pc;
    reg we=0,mode=0;reg [7:0] x=0,y=0;reg [17:0] colour=0;
    wire ready,overflow,lr,lf,ld;wire [31:0] captured,displayed;
    wire [7:0] ln,ra;wire [15:0] data;wire initialized,sclk,mosi,dc,cs,rst;
    gba_lines lines(.core_clk(cc),.core_reset(reset),.pixel_we(we),.pixel_x(x),.pixel_y(y),
        .pixel_data(colour),.mode_toggle(mode),.video_ready(ready),.overflow(overflow),.captured_frames(captured),
        .panel_clk(pc),.panel_reset(reset),.rd_addr(ra),.rd_data(data),.line_ready(lr),
        .line_number(ln),.line_fitted(lf),.line_done(ld));
    // Shorten millisecond delays, retain the actual initializer and SPI master.
    gba_display #(.CLK_HZ(1000)) display(.clk(pc),.resetn(!reset),.line_ready(lr),.line_fitted(lf),
        .line_number(ln),.line_done(ld),.rd_addr(ra),.rd_data(data),.initialized(initialized),
        .displayed_frames(displayed),.sclk(sclk),.mosi(mosi),.dc(dc),.cs_n(cs),.rst_n(rst));
    function [17:0] source(input integer sx,input integer sy);
        reg [5:0] r,g,b;begin r=sx%64;g=sy%64;b=(sx+sy)%64;source={b,g,r};end
    endfunction
    function integer expand(input integer coordinate);
        begin expand=(coordinate/4)*5+(coordinate%4>=2 ? coordinate%4+1 : coordinate%4);end
    endfunction
    integer pixels=0,bits=0,frame=0,col,row,sx,sy,x0,y0,w,h;reg [15:0] received,expected;reg [17:0] original;
    always @(posedge sclk) if(!display.init_owner&&!cs&&dc) begin
        received={received[14:0],mosi};bits=bits+1;
        if(bits==16)begin
            bits=0;col=pixels%240;row=pixels/240;
            x0=frame==0 ? 24 : 0;y0=frame==0 ? 56 : 40;w=frame==0 ? 192 : 240;h=frame==0 ? 128 : 160;
            expected=0;
            if(col>=x0&&col<x0+w&&row>=y0&&row<y0+h)begin
                sx=frame==0 ? expand(col-x0) : col-x0;sy=frame==0 ? expand(row-y0) : row-y0;
                original=source(sx,sy);expected={original[17:13],original[11:6],original[5:1]};
            end
            if(received!==expected)$fatal(1,"Frame %d pixel (%d,%d) = %h expected %h",frame,col,row,received,expected);
            pixels=pixels+1;
            if(pixels==57600)begin pixels=0;frame=frame+1;end
        end
    end
    integer f,ix,iy;
    initial begin
        force display.init.rom_pause_r=0;
        force display.init.rom_pause_nz_r=0;
        #200;@(negedge cc);reset=0;
        for(f=0;f<2;f=f+1)begin
            if(f==1)mode=1;
            for(iy=0;iy<160;iy=iy+1)begin
                @(negedge cc);we=0;wait(ready);
                for(ix=0;ix<240;ix=ix+1)begin
                    @(negedge cc);we=1;x=ix;y=iy;colour=source(ix,iy);
                end
                @(negedge cc);we=0;
            end
        end
        wait(displayed==2);#100;
        if(frame!=2||overflow||captured!=2)$fatal(1,"FIFO/frame accounting");
        $display("PASS display: all 115200 SPI pixels, fitted/native viewports, black borders, RGB565, async backpressure");$finish;
    end
    initial begin #100000000;$fatal(1,"Display timeout frame=%d captured=%d",frame,captured);end
endmodule
