`timescale 1ns/1ps
module tb_gba_flash #(
    parameter real CORE_HALF_NS=25,
    parameter real FLASH_HALF_NS=10
);
    reg clk=0,fast_clk=0,reset=1,request=0;
    always #(CORE_HALF_NS) clk=~clk;
    initial begin #2.3; forever #(FLASH_HALF_NS) fast_clk=~fast_clk; end
    reg [24:0] address=0;
    wire done,sck,cs,mosi;reg miso=0;
    wire [31:0] data,second,misses;
    gba_flash dut(.clk(clk),.clk_flash(fast_clk),.reset(reset),.request(request),
        .address(address),.done(done),.data(data),.second_data(second),
        .flash_clk(sck),.flash_cs_n(cs),.flash_mosi(mosi),.flash_miso(miso),.misses(misses));
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
    always @(negedge cs)begin transactions=transactions+1;bits=0;command=0;physical=0;end
    always @(posedge sck)if(!cs)begin
        if(bits<8)command={command[6:0],mosi};
        else if(bits<32)physical={physical[22:0],mosi};
        bits=bits+1;
    end
    always @(negedge sck)begin
        if(!cs&&bits>=40)begin
            read_bit=bits-40;byte_address=(physical-24'h100000)+(read_bit>>3);
            modeled=rom_byte(byte_address);miso<=#12 modeled[7-(read_bit&7)];
        end else miso=0;
    end
    always @(posedge cs)if(!reset&&bits!=0)begin
        if(bits!=2088||command!=8'h0b)$fatal(1,"Wrong flash transaction");
        if(physical[7:0]!=0||physical<24'h100000||physical>=24'h900000)$fatal(1,"Wrong flash offset %h",physical);
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
        for(i=0;i<64;i=i+1)check_word(i);
        if(transactions!=1||misses!=1)$fatal(1,"Cache line did not hit");
        check_word(21'h12345);check_word(21'h12344);check_word(21'h1237f);
        if(transactions!=2||misses!=2)$fatal(1,"Nonzero cache tag/pair hit failed");
        check_word(21'h1fffff);check_word(21'h1ffffe);
        if(transactions!=3||misses!=3)$fatal(1,"Upper ROM boundary failed");
        check_word(0);if(transactions!=4)$fatal(1,"Cache replacement failed");
        reset=1;repeat(8)@(negedge clk);reset=0;
        check_word(1);if(transactions!=5||misses!=1)$fatal(1,"Reset did not invalidate cache");
        $display("PASS GBA flash: physical offset, 8 MiB boundary, little-endian word pairs, cache hits/replacement, reset, async FIFO");$finish;
    end
    initial begin #10000000;$fatal(1,"Flash simulation timeout");end
endmodule
