`timescale 1ns/1ps
module tb_gba_qspi #(
    parameter QE_FAIL=0, CLOCK_CYCLES=4, RX_REGISTER=0, OUTPUT_DELAY_NS=12,
    parameter real CORE_HALF_NS=25,
    parameter real FLASH_HALF_NS=10
);
    reg clk=0,fast_clk=0,reset=1,request=0;
    always #(CORE_HALF_NS) clk=~clk;
    initial begin #2.3; forever #(FLASH_HALF_NS) fast_clk=~fast_clk; end
    reg [24:0] address=0;
    wire done,sck,cs,mosi,oe,ready,fault;reg miso=0;
    wire [3:0] dq;reg [3:0] response=0;reg drive_quad=0;
    assign dq[0]=oe?mosi:1'bz;
    assign dq=drive_quad?response:4'bzzzz;
    reg [7:0] sr2=8'h40;reg volatile_enabled=0;integer volatile_writes=0;
    real last_falling=0;reg [7:0] status_value;
    wire [31:0] data,second,misses;
    gba_flash #(.QSPI(1),.CLOCK_CYCLES(CLOCK_CYCLES),.RX_REGISTER(RX_REGISTER)) dut(.clk(clk),.clk_flash(fast_clk),.reset(reset),.request(request),
        .address(address),.done(done),.data(data),.second_data(second),
        .flash_clk(sck),.flash_cs_n(cs),.flash_mosi(mosi),.flash_miso(drive_quad?dq[1]:miso),.quad_other({dq[3:2],dq[0]}),
        .mosi_oe(oe),.quad_ready(ready),.quad_fault(fault),.misses(misses));
    integer transactions=0,bits=0,read_bit;
    reg [7:0] command=0,modeled;
    reg [23:0] physical=0;
    reg [22:0] byte_address;
    function automatic [7:0] rom_byte(input [22:0] a);
        rom_byte=((a*23'd37)^(a>>8)^(a>>16)^23'h0000a5)&8'hff;
    endfunction
    function automatic [31:0] rom_word(input [20:0] a);
        reg [22:0] b;
        begin b={a,2'b00};rom_word={rom_byte(b+23'd3),rom_byte(b+23'd2),rom_byte(b+23'd1),rom_byte(b)};end
    endfunction
    always @(posedge oe)if(drive_quad&&!cs)$fatal(1,"IO0 drives before quad CS release");
    always @(negedge cs)begin bits=0;command=0;physical=0;status_value=0;drive_quad=0;end
    always @(posedge sck)if(!cs)begin
        if(bits<8)command={command[6:0],mosi};
        else if(command==8'h6b&&bits<32)physical={physical[22:0],mosi};
        else if(command==8'h31&&bits<16)status_value={status_value[6:0],mosi};
        if(command==8'h6b&&bits>=40)begin
            if(oe||!sr2[1])$fatal(1,"Quad data contention or QE disabled");
        end
        bits=bits+1;
    end
    always @(negedge sck)begin
        last_falling=$realtime;
        if(!cs&&command==8'h35&&bits>=8&&bits<16)miso<=#(OUTPUT_DELAY_NS) sr2[15-bits];
        if(!cs&&command==8'h6b&&bits>=40&&bits<552)begin
            read_bit=bits-40;byte_address=(physical-24'h100000)+(read_bit>>1);
            modeled=rom_byte(byte_address);drive_quad=1;
            response<=#(OUTPUT_DELAY_NS) ((read_bit&1)==0?modeled[7:4]:modeled[3:0]);
        end
    end
    always @(posedge cs)begin
        drive_quad=0;
        if(!reset&&bits!=0)case(command)
            8'h35:if(bits!=16)$fatal(1,"SR2 read framing");
            8'h50:begin if(bits!=8)$fatal(1,"Volatile enable framing");volatile_enabled=1;end
            8'h31:begin
                if(bits!=16||!volatile_enabled||status_value!=8'h42)$fatal(1,"Unsafe SR2 write");
                if(!QE_FAIL)sr2=status_value;volatile_enabled=0;volatile_writes=volatile_writes+1;
            end
            8'h6b:begin
                transactions=transactions+1;
                if(bits!=552)$fatal(1,"Wrong quad transaction clocks %0d",bits);
                if(physical[7:0]!=0||physical<24'h100000||physical>=24'h900000)$fatal(1,"Wrong offset");
            end
            default:$fatal(1,"Forbidden flash command %h",command);
        endcase
    end
    task automatic check_word(input [20:0] a);
        integer timeout;
        begin
            @(negedge clk);address={4'b0,a};request=1;
            @(negedge clk);request=0;timeout=0;
            while(!done&&timeout<25000)begin @(negedge clk);timeout=timeout+1;end
            if(!done)$fatal(1,"Flash timeout %h",a);
            if(data!==rom_word(a)||second!==rom_word(a^21'd1))
                $fatal(1,"Flash pair mismatch %h got %h/%h expected %h/%h",a,data,second,rom_word(a),rom_word(a^21'd1));
            repeat(3)@(negedge clk);
        end
    endtask
    integer i;
    initial begin
        repeat(8)@(negedge clk);reset=0;
        if(QE_FAIL)begin
            wait(fault);
            if(ready||transactions!=0)$fatal(1,"QE failure allowed quad reads");
            $display("PASS GBA QSPI: failed QE write stops reads and reports fault");$finish;
        end
        for(i=0;i<64;i=i+1)check_word(i);
        if(transactions!=1||misses!=1)$fatal(1,"Cache line did not hit");
        check_word(21'h12345);check_word(21'h12344);check_word(21'h1237f);
        if(transactions!=2||misses!=2)$fatal(1,"Nonzero cache tag/pair hit failed");
        check_word(21'h1fffff);check_word(21'h1ffffe);
        if(transactions!=3||misses!=3)$fatal(1,"Upper ROM boundary failed");
        check_word(0);if(transactions!=4)$fatal(1,"Cache replacement failed");
        reset=1;repeat(8)@(negedge clk);reset=0;
        check_word(1);if(transactions!=5||misses!=1)$fatal(1,"Reset did not invalidate cache");
        // Abort an in-flight miss and restart with a distinct line.
        @(negedge clk);address=21'h4444;request=1;
        @(negedge clk);request=0;
        wait(!cs&&command==8'h6b&&bits>48);
        @(negedge clk);reset=1;repeat(8)@(negedge clk);reset=0;
        check_word(21'h5555);
        if(fault||!ready||volatile_writes!=1||sr2!=8'h42)$fatal(1,"QE/init/reset failed");
        $display("PASS GBA QSPI: volatile QE preserves SR2, IO0 release, 552 clocks, reset during read; physical offset, 8 MiB boundary, little-endian word pairs, cache hits/replacement, reset, async FIFO");$finish;
    end
    initial begin #10000000;$fatal(1,"Flash simulation timeout");end
endmodule
