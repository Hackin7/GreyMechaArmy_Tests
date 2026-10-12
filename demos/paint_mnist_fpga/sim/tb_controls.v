`timescale 1ns/1ps
module tb_controls;
    reg clk=0; always #5 clk=~clk;
    reg resetn=0;
    reg [5:0] raw=6'b111111;
    wire [5:0] filtered;
    paint_buttons #(.STABLE_CYCLES(5)) debounce(.clk(clk),.resetn(resetn),
        .buttons_n(raw),.pressed(filtered));
    reg [5:0] pressed=0;
    reg done=0;
    wire [2:0] colour,selected;
    wire [6:0] x;
    wire [5:0] y;
    wire [783:0] snapshot;
    wire request,valid,busy,updating;
    wire [3:0] prediction;
    reg [9:0] address=0;
    paint_ui #(.HOLD_CYCLES(4),.REPEAT_CYCLES(2),.INTERVAL_CYCLES(5000)) dut (
        .clk(clk),.resetn(resetn),.pressed(pressed),.render_address(address),
        .render_colour(colour),.cursor_x(x),.cursor_y(y),.chosen_colour(selected),
        .snapshot(snapshot),.request_toggle(request),.done_toggle(done),.result_digit(4'd7),
        .prediction(prediction),.prediction_valid(valid),.updating(updating),.busy(busy));
    integer i;
    reg [783:0] saved;
    reg old_request;
    task wait_cycles(input integer n);
        begin repeat(n) @(negedge clk); end
    endtask
    task move_to(input integer gx,gy);
        begin
            while(x!=gx || y!=gy) begin
                pressed[3:0]=0;
                if(x>gx) pressed[0]=1;
                if(x<gx) pressed[3]=1;
                if(y>gy) pressed[1]=1;
                if(y<gy) pressed[2]=1;
                @(negedge clk);
            end
            pressed[3:0]=0; wait_cycles(2);
        end
    endtask
    initial begin
        wait_cycles(4); resetn=1;
        // A two-cycle bounce must not become a press. Other buttons cannot reset its filter.
        raw[0]=0; wait_cycles(2); raw[0]=1; wait_cycles(8);
        if(filtered!=0) $fatal(1,"Bounce admitted");
        raw[0]=0; wait_cycles(4); raw[4]=0; wait_cycles(4);
        if(!filtered[0]) $fatal(1,"Independent debounce lost first button");
        wait_cycles(4); if(!filtered[4]) $fatal(1,"Second button did not debounce");
        raw=6'b111111; wait_cycles(8); if(filtered!=0) $fatal(1,"Release did not debounce");
        wait(!dut.clearing); @(negedge clk);
        if(x!=28 || y!=28 || selected!=3 || valid) $fatal(1,"Wrong startup state");
        pressed[3:0]=4'b1001; wait_cycles(10);
        if(x!=28 || y!=28) $fatal(1,"Opposite directions moved cursor");
        pressed[3:0]=4'b1010; wait_cycles(1);
        if(x!=29 || y!=27) $fatal(1,"Immediate diagonal movement failed");
        wait_cycles(3); if(x!=29) $fatal(1,"Initial hold delay too short");
        wait_cycles(1); if(x!=30) $fatal(1,"Hold repeat failed");
        pressed=0; move_to(0,0); pressed[0]=1; pressed[1]=1; wait_cycles(12);
        if(x!=0 || y!=0) $fatal(1,"Upper boundary failed");
        pressed=0; move_to(95,63); pressed[3]=1; pressed[2]=1; wait_cycles(12);
        if(x!=95 || y!=63) $fatal(1,"Lower boundary failed");
        pressed=0; move_to(85,10);
        pressed[4]=1; wait_cycles(3);
        if(selected!=1) $fatal(1,"Palette click failed");
        move_to(70,10); if(selected!=1) $fatal(1,"Held A incorrectly changed palette");
        pressed[4]=0; wait_cycles(2); pressed[4]=1; wait_cycles(2);
        if(selected!=3) $fatal(1,"Red selection failed");
        pressed[4]=0; wait_cycles(2); move_to(0,0); address=0;
        pressed[4]=1;
        wait(dut.copying); @(negedge clk);
        if(colour!=3) $fatal(1,"Painting at canvas origin failed");
        pressed[3]=1;
        wait(dut.in_flight); @(negedge clk); saved=snapshot;
        if(!snapshot[0]) $fatal(1,"Origin missing from snapshot");
        wait_cycles(15);
        if(x==0 || snapshot!==saved) $fatal(1,"Drawing stalled or snapshot changed in flight");
        pressed[4]=0; pressed[3]=0; wait_cycles(2);
        old_request=request; done=~done; wait_cycles(4);
        if(!valid || prediction!=7) $fatal(1,"Completion transfer failed");
        // Changed canvas must not launch again until the 5000-cycle interval expires.
        wait_cycles(20); if(request!=old_request) $fatal(1,"Recognition interval ignored");
        // Clear with pen held invalidates the prediction and requires release before drawing.
        pressed[4]=1; pressed[5]=1; wait_cycles(2); pressed[5]=0;
        wait(!dut.clearing); wait_cycles(4);
        if(valid) $fatal(1,"Clear retained prediction");
        for(i=0;i<784;i=i+1) if(dut.canvas[i]!=0) $fatal(1,"Clear while A held repainted canvas");
        pressed[4]=0; wait_cycles(2); pressed[4]=1;
        wait(dut.in_flight); @(negedge clk); saved=snapshot;
        pressed[5]=1; wait_cycles(2); pressed[5]=0;
        wait(!dut.clearing); wait_cycles(3);
        if(snapshot!==saved) $fatal(1,"Clear modified snapshot while NN reads it");
        done=~done; wait_cycles(5);
        if(valid || busy) $fatal(1,"Stale in-flight result restored after clear");
        $display("PASS controls: debounce, repeat, bounds, palette, hold/release, snapshot, clear/stale result");
        $finish;
    end
    initial begin #5000000; $fatal(1,"Controls timeout"); end
endmodule
