`timescale 1ns/1ps
module tb_sccb #(parameter HOLD=0);
    reg clk=0; always #5 clk=~clk;
    reg resetn=0;
    tri1 sda, scl;
    wire scl_low,sda_low,sensor_reset_n,configured,live;
    wire [2:0] error_code;
    wire [7:0] product_id,version;
    reg sensor_low=0;
    assign sda=(sda_low || sensor_low) ? 1'b0 : 1'bz;
    assign scl=scl_low ? 1'b0 : 1'bz;
    ov7670_config #(.CLK_HZ(10000),.QUARTER_CYCLES(4),
        .RESET_CYCLES(5),.SETTLE_CYCLES(10),.BAR_CYCLES(2000),
        .HOLD_COLOR_BARS(HOLD)) dut(
        .clk(clk),.resetn(resetn),.sda_in(sda),.scl_low(scl_low),.sda_low(sda_low),
        .sensor_reset_n(sensor_reset_n),.configured(configured),.live(live),
        .error_code(error_code),.product_id(product_id),.version(version));

    // Independent SCCB slave: decode address, subaddress, data, ACK and reads.
    reg [7:0] registers[0:255];
    reg [7:0] received=0,pointer=0,transmitted=0;
    reg active=0,reading=0,next_read=0,ack_seen=0,read_finished=0;
    integer bit_count=0,byte_count=0,mode=0,transactions=0,writes=0;
    integer n;
    reg last_was_bars=0,saw_live_write=0;
    always @(negedge sda) if(scl && resetn) begin
        active=1; reading=0; next_read=0; ack_seen=0; read_finished=0;
        bit_count=0; byte_count=0; received=0; transactions=transactions+1;
    end
    always @(posedge sda) if(scl) begin active=0; sensor_low=0; end
    always @(posedge scl) if(active && !read_finished) begin
        if(bit_count<8) begin
            if(!reading) received={received[6:0],sda};
            bit_count=bit_count+1;
        end else begin
            bit_count=0; ack_seen=1;
            if(reading) begin
                if(sda!==1) $fatal(1,"Master did not NACK final read byte");
                read_finished=1;
            end else begin
                if(byte_count==0) begin
                    if(received!=8'h42 && received!=8'h43) $fatal(1,"Wrong SCCB address %h",received);
                    next_read=received[0];
                end else if(byte_count==1) pointer=received;
                else if(byte_count==2 && mode!=1 && !(mode==4 && transactions==1)) begin
                    registers[pointer]=received; writes=writes+1;
                    if(pointer==8'h42) begin
                        if(received==8'h08) last_was_bars=1;
                        else if(received==0 && last_was_bars) saw_live_write=1;
                    end
                end
                byte_count=byte_count+1;
            end
        end
    end
    always @(negedge scl) begin
        if(!active || read_finished) sensor_low=0;
        else if(bit_count==8) begin
            sensor_low=!reading && mode!=1 && !(mode==4 && transactions==1);
        end else begin
            if(ack_seen) begin
                ack_seen=0;
                if(next_read) begin reading=1; transmitted=registers[pointer]; end
            end
            sensor_low=reading && !transmitted[7-bit_count];
        end
    end
    task boot(input integer new_mode);
        resetn=0; sensor_low=0; active=0; bit_count=0;
        mode=new_mode; transactions=0; writes=0; last_was_bars=0; saw_live_write=0;
        for(n=0;n<256;n=n+1) registers[n]=0;
        registers[8'h0a]=new_mode==2 ? 8'h00 : 8'h76;
        registers[8'h0b]=new_mode==3 ? 8'h00 : 8'h73;
        repeat(10) @(negedge clk); resetn=1;
    endtask
    initial begin
        boot(0);
        wait(configured || error_code);
        if(error_code || product_id!=8'h76 || version!=8'h73) $fatal(1,"Sensor identity %h/%h error %d",product_id,version,error_code);
        if(registers[8'h12]!=4 || registers[8'h40]!=8'hd0 || registers[8'h72]!=8'h22)
            $fatal(1,"RGB565 QQVGA configuration missing");
        if(registers[8'h13]!=8'he7 || !last_was_bars || live) $fatal(1,"Colour bars/AEC/AGC/AWB");
        if(HOLD) begin
            repeat(4000) @(negedge clk);
            if(!configured || live || saw_live_write) $fatal(1,"Colour bars not held");
            $display("PASS SCCB: hold-colour-bars diagnostic build"); $finish;
        end
        wait(live || error_code);
        if(error_code || !saw_live_write || registers[8'h42]!=0) $fatal(1,"Live transition");
        boot(1); wait(error_code);
        if(error_code!=1 || configured || transactions!=3 || dut.last_nacks!=4'b0111)
            $fatal(1,"NACK/retry policy %d transactions %d nack mask %b",error_code,transactions,dut.last_nacks);
        boot(2); wait(error_code); if(error_code!=2 || configured) $fatal(1,"Wrong PID accepted");
        boot(3); wait(error_code); if(error_code!=3 || configured) $fatal(1,"Wrong VER accepted");
        boot(4); wait(live || error_code);
        if(error_code || !live || !saw_live_write) $fatal(1,"Transient NACK recovery");
        $display("PASS SCCB: decoded writes/reads, IDs, bars/live, NACK retries and recovery"); $finish;
    end
    initial begin #10000000; $fatal(1,"SCCB timeout state %d operation %d",dut.state,dut.operation); end
endmodule
