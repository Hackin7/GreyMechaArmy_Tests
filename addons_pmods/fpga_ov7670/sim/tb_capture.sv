`timescale 1ns/1ps
module tb_capture;
    localparam W=4,H=3;
    reg clk=0; always #5 clk=~clk;
    reg pclk=0,pclk_running=1; always #17 if(pclk_running) pclk=~pclk;
    reg resetn=0,configured=0,href=0,vsync=0,frame_boundary=0;
    reg [7:0] data=0;
    wire ack_toggle,request_toggle,write_enable,write_bank,malformed;
    wire [14:0] write_address;
    wire [15:0] write_data,read_data;
    reg [14:0] read_address=0;
    wire valid,frame_accepted;
    integer accepted=0,i;
    camera_capture #(.WIDTH(W),.HEIGHT(H)) capture(.*);
    camera_framebuffer #(.WIDTH(W),.HEIGHT(H)) buffer(.*);
    always @(posedge clk) if(resetn && frame_accepted) accepted=accepted+1;
    always @(posedge pclk)
        if(resetn && valid && write_enable && write_bank==buffer.read_bank)
            $fatal(1,"Capture overwrote display bank");
    task pticks(input integer n); repeat(n) @(negedge pclk); endtask
    task boundary;
        repeat(5) @(negedge clk);
        frame_boundary=1; @(negedge clk); frame_boundary=0;
        repeat(5) @(negedge clk);
    endtask
    task frame(input integer seed,input integer defect);
        integer x,y,n,rows;
        reg [15:0] pixel;
        vsync=1; href=0; pticks(4); vsync=0; pticks(3);
        rows=H+(defect==3 ? 1:0)-(defect==4 ? 1:0);
        for(y=0;y<rows;y=y+1) begin
            n=W*2;
            if(y==H-1 && defect==1) n=n-1;
            if(y==0 && defect==2) n=n+2;
            for(x=0;x<n;x=x+1) begin
                href=1; pixel=seed+y*W+x/2;
                data=x%2==0 ? pixel[15:8]:pixel[7:0]; pticks(1);
            end
            href=0; pticks(3);
        end
        vsync=1; pticks(4); // stay in inter-frame VSYNC until the next frame
    endtask
    task check(input integer seed);
        for(i=0;i<W*H;i=i+1) begin
            @(negedge clk); // launch before three complete read-clock edges
            read_address=i; repeat(3) @(negedge clk);
            if(read_data !== 16'(seed+i))
                $fatal(1,"Read addr %0d expected %h got %h",i,16'(seed+i),read_data);
        end
    endtask
    initial begin
        pticks(4); resetn=1; configured=1; pticks(5);
        frame('h1200,0);
        if(valid) $fatal(1,"Swapped without boundary");
        // Pending complete bank must survive another entire incoming frame.
        frame('h3400,0); boundary();
        if(!valid || accepted!=1) $fatal(1,"First handoff");
        check('h1200);
        if(malformed) $fatal(1,"Well-formed input flagged malformed");
        pticks(10); frame('h5600,0); check('h1200);
        boundary(); if(accepted!=2) $fatal(1,"Second handoff"); check('h5600);
        pticks(10); frame('h7800,1); boundary();
        if(accepted!=2 || !malformed) $fatal(1,"Odd/truncated line accepted");
        check('h5600);
        frame('h7800,2); boundary(); if(accepted!=2) $fatal(1,"Long line accepted");
        frame('h7800,3); boundary(); if(accepted!=2) $fatal(1,"Extra row accepted");
        frame('h7800,4); boundary(); if(accepted!=2) $fatal(1,"Missing row accepted");
        // Premature VSYNC, zero-line frame, then recover.
        vsync=1; pticks(4); vsync=0; pticks(4); vsync=1; pticks(4); vsync=0;
        boundary(); if(accepted!=2) $fatal(1,"Empty frame accepted");
        frame('h9a00,0); boundary(); if(accepted!=3) $fatal(1,"No recovery"); check('h9a00);
        repeat(300) @(negedge clk); check('h9a00); // stale frame retained
        resetn=0; pticks(2);
        if(request_toggle!==0 || valid!==0) $fatal(1,"Reset ownership");
        resetn=1; pticks(5); frame('hbc00,0); boundary(); check('hbc00);
        @(negedge pclk); pclk_running=0; resetn=0;
        repeat(5) @(negedge clk);
        if(request_toggle!==0 || write_enable!==0 || valid!==0)
            $fatal(1,"Reset failed with stopped PCLK");
        $display("PASS capture: byte order, CDC, ownership, dropped/malformed frames, recovery"); $finish;
    end
    initial begin #1000000; $fatal(1,"Timeout"); end
endmodule
