`timescale 1ns/1ps
module tb_triple;
    reg clk=0,clk_running=1;always #5 if(clk_running) clk=~clk;
    reg pclk=0,running=1;always #17 if(running) pclk=~pclk;
    reg resetn=0,configured=0,href=0,vsync=0;
    reg [7:0] data=0;
    reg display_start=0,display_done=0;
    wire [2:0] ready_toggle,release_toggle;
    wire write_enable,malformed,pending_valid,display_busy,valid,frame_accepted;
    wire [1:0] write_bank,read_bank;
    wire [14:0] write_address;
    wire [15:0] write_data;
    wire [31:0] valid_frames,malformed_frames,dropped_frames,replaced_frames;
    reg [15:0] mem[0:35];
    integer accepted=0,i;
    camera_capture3 #(.WIDTH(4),.HEIGHT(3)) capture(.*);
    camera_queue3 queue(.*);
    always @(posedge pclk) if(write_enable) begin
        if(display_busy && write_bank==read_bank) $fatal(1,"Write into displayed bank");
        if(ready_toggle[write_bank]!=release_toggle[write_bank]) $fatal(1,"Write into unreleased bank");
        mem[write_bank*12+write_address]<=write_data;
    end
    always @(posedge clk) if(frame_accepted) accepted=accepted+1;
    task pt(input integer n);repeat(n) @(negedge pclk);endtask
    task frame(input integer seed,input integer defect);
        integer x,y,n,rows;
        reg [15:0] pixel;
        vsync=1;href=0;pt(4);vsync=0;pt(3);
        rows=3+(defect==3)-(defect==4);
        for(y=0;y<rows;y=y+1) begin
            n=8-((defect==1)&&(y==2))+2*((defect==2)&&(y==0));
            for(x=0;x<n;x=x+1) begin
                href=1;pixel=seed+y*4+x/2;data=x%2 ? pixel[7:0]:pixel[15:8];pt(1);
            end
            href=0;pt(3);
        end
        vsync=1;pt(8);
    endtask
    task start_display;
        wait(pending_valid);@(negedge clk);display_start=1;
        @(negedge clk);display_start=0;repeat(3) @(negedge clk);
    endtask
    task finish_display;
        @(negedge clk);display_done=1;@(negedge clk);display_done=0;
        repeat(8) @(negedge clk);
    endtask
    task check(input integer seed);
        for(i=0;i<12;i=i+1)
            if(mem[read_bank*12+i] !== 16'(seed+i)) $fatal(1,"Torn/wrong bank at %d",i);
    endtask
    initial begin
        pt(4);resetn=1;configured=1;pt(6);
        frame('h1200,0);start_display();check('h1200);
        frame('h3400,0);check('h1200);
        frame('h5600,0);check('h1200);
        if(replaced_frames!=1) $fatal(1,"Pending latest-frame replacement");
        finish_display();start_display();check('h5600);finish_display();
        frame('h7800,1);frame('h7800,2);frame('h7800,3);frame('h7800,4);
        if(malformed_frames!=4 || !malformed || pending_valid) $fatal(1,"Malformed rejection");
        frame('h9a00,0);start_display();check('h9a00);finish_display();
        // Capture faster than display, then resume without corruption.
        for(i=0;i<10;i=i+1) frame('hbc00+i*16,0);
        start_display();check('hbc90);finish_display();
        if(valid_frames!=14 || accepted!=4) $fatal(1,"Frame accounting %d %d",valid_frames,accepted);
        // A stopped consumer fills all three banks. The fourth complete
        // frame must count as dropped without overwriting any published data.
        pt(8);@(negedge clk);clk_running=0;
        frame('h1000,0);frame('h2000,0);frame('h3000,0);frame('h4000,0);
        if(dropped_frames!=1 || valid_frames!=18) $fatal(1,"No-free-bank accounting");
        clk_running=1;repeat(20) @(negedge clk);
        start_display();check('h3000);finish_display();
        @(negedge pclk);running=0;resetn=0;repeat(5) @(negedge clk);
        if(ready_toggle!==0 || write_enable!==0 || pending_valid!==0 || valid!==0)
            $fatal(1,"Reset while PCLK stopped");
        $display("PASS triple: asynchronous ownership, latest pending, malformed frames, overload, stopped-clock reset");$finish;
    end
    initial begin #2000000;$fatal(1,"Timeout");end
endmodule
