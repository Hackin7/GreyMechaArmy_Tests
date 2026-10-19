`timescale 1ns/1ps
module tb_panel;
    reg clk=0; always #5 clk=~clk;
    reg resetn=0;
    reg [15:0] pixel_data=16'h07e0;
    wire [15:0] pixel_index;
    wire oled_scl,oled_sda,oled_dc,oled_cs,oled_rst;
    wire init_done,streaming,frame_boundary;
    integer frames=0,pixels=0,bits=0;
    reg [15:0] shift=0;
    oled_gc9a01 #(.CLK_HZ(1000),.SWAP_RB(1)) dut(.*);
    always @(posedge oled_scl) if(streaming && !oled_cs) begin
        if(!init_done || !oled_dc) $fatal(1,"Panel streamed before init/data mode");
        shift={shift[14:0],oled_sda}; bits=bits+1;
        if(bits==16) begin
            if(shift !== (frames==0 ? 16'h07e0:16'h001f))
                $fatal(1,"Panel frame %0d pixel %0d got %h",frames,pixels,shift);
            bits=0; pixels=pixels+1;
        end
    end
    always @(posedge frame_boundary) begin
        if(pixels!=57600 || bits!=0 || !oled_cs)
            $fatal(1,"Unsafe panel boundary: %0d pixels, %0d bits, CS=%b",pixels,bits,oled_cs);
        frames=frames+1; pixels=0; pixel_data=16'hf800;
        $display("Panel frame %0d complete",frames);
        if(frames==2) begin
            $display("PASS panel: real initialization, two full frames, safe boundary/rearm and R/B swap");
            $finish;
        end
    end
    initial begin
        // ROM pauses are precomputed for 75 MHz; shorten only those waits.
        // Keep the real initialization commands, SPI engine and rearm FSM.
        force dut.u_init.rom_pause_r=32'd1;
        repeat(5) @(negedge clk); resetn=1;
        wait(init_done);
        // The ROM is unused after initialization. Avoid repeatedly walking
        // its large case tables at the last index during long SPI frames.
        force dut.u_init.init_idx=0;
        $display("Panel initialization complete");
    end
    initial begin #100000000; $fatal(1,"Panel timeout"); end
endmodule
