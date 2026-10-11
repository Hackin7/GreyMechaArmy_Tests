`timescale 1ns/1ps
module tb_flash_fifo;
    reg wr_clk=0, rd_clk=0, reset=1;
    always #7.8125 wr_clk=~wr_clk;
    initial begin #2.7; forever #31.25 rd_clk=~rd_clk; end
    reg wr_en=0, rd_en=0;
    reg [15:0] wr_data=0;
    wire [15:0] rd_data;
    wire full, empty;
    integer sent=0, received=0, full_cycles=0, epoch;
    gb_flash_fifo dut (.wr_clk(wr_clk),.wr_reset(reset),.wr_en(wr_en),
        .wr_data(wr_data),.full(full),.rd_clk(rd_clk),.rd_reset(reset),
        .rd_en(rd_en),.rd_data(rd_data),.empty(empty));
    always @(negedge wr_clk) begin
        wr_en = !reset && sent<2000 && !full && ($urandom_range(0,3)!=0);
        wr_data = sent ^ 16'h55aa;
    end
    always @(posedge wr_clk) begin
        if (reset) sent=0;
        else if (wr_en && !full) sent=sent+1;
        else if (full) full_cycles=full_cycles+1;
    end
    always @(negedge rd_clk)
        rd_en = !reset && !empty && ($urandom_range(0,3)!=0);
    always @(posedge rd_clk) begin
        if (reset) received=0;
        else if (rd_en && !empty) begin
            if (rd_data !== ((received ^ 16'h55aa) & 16'hffff))
                $fatal(1,"FIFO order mismatch at %0d: %h",received,rd_data);
            received=received+1;
        end
    end
    initial begin
        for (epoch=0; epoch<2; epoch=epoch+1) begin
            reset=1;
            repeat(5) @(negedge rd_clk);
            reset=0;
            wait(received==2000);
            repeat(5) @(negedge rd_clk);
            if (!empty) $fatal(1,"FIFO not empty after drain");
        end
        if (full_cycles==0) $fatal(1,"FIFO full/backpressure not exercised");
        $display("PASS asynchronous FIFO: 4000 ordered records, reset, full, empty");
        $finish;
    end
    initial begin #2000000; $fatal(1,"FIFO timeout"); end
endmodule
