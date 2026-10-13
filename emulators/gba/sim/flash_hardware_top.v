// Read-only hardware experiment using the actual GBA flash cache and host.
// Host memory reads address cartridge bytes; writes acknowledge without effect.
module top #(parameter FLASH_QSPI=0, FLASH_CYCLES=4, FLASH_RX_REGISTER=0, PLL_CORE_DIV=20, PLL_FLASH_DIV=8)(
    input wire host_sck,host_mosi,host_cs_n,output wire host_miso,
    output wire flash_cs_n,inout wire flash_mosi,
    input wire flash_miso,flash_io2,flash_io3,
    output wire [7:0] led,output wire clock_ref
);
    wire osc,clk,clk_panel,clk_flash,locked;
    OSCG #(.DIV(6)) oscillator(.OSC(osc));
    gba_pll #(.CORE_DIV(PLL_CORE_DIV),.FLASH_DIV(PLL_FLASH_DIV)) clocks(.osc(osc),.reset(1'b0),.core_clk(clk),
        .panel_clk(clk_panel),.flash_clk(clk_flash),.locked(locked));
    reg [7:0] startup=0;
    reg [15:0] reference_divider=0;
    always @(posedge clk)begin
        reference_divider<=reference_divider+1'b1;
        if(!locked)startup<=0;else if(!(&startup))startup<=startup+1'b1;
    end
    assign clock_ref=reference_divider[15];
    wire reset=!(&startup);
    wire [7:0] rx,tx;wire rv,tv,tr;
    gb_spi_phy phy(.clk(clk),.reset(reset),.spi_sck(host_sck),
        .spi_mosi(host_mosi),.spi_csn(host_cs_n),.spi_miso(host_miso),
        .rx_data(rx),.rx_valid(rv),.tx_data(tx),.tx_valid(tv),.tx_ready(tr));
    wire request,read,done,reset_pulse,busy;
    wire [22:0] address;wire [31:0] data,second,misses;
    wire mosi_out,oe,sck,qready,qfault;
    reg [1:0] ready_sync=0,fault_sync=0;
    reg [5:0] reset_hold=0;
    always @(posedge clk)begin
        ready_sync<={ready_sync[0],qready};fault_sync<={fault_sync[0],qfault};
        if(reset||reset_pulse)reset_hold<=63;
        else if(reset_hold!=0)reset_hold<=reset_hold-1'b1;
    end
    wire reader_reset=reset||reset_hold!=0;
    reg active=0;reg [31:0] cycles=0;
    always @(posedge clk)begin
        if(reader_reset)begin active<=0;cycles<=0;end
        else begin
            if(request&&read)active<=1;
            if(active)cycles<=cycles+1'b1;
            if(done)active<=0;
        end
    end
    gba_host host(.clk(clk),.reset(reset),.rx_data(rx),.rx_valid(rv),
        .tx_data(tx),.tx_valid(tv),.tx_ready(tr),.run(),.pause(),.reset_pulse(reset_pulse),
        .max_rom_addr(),.flash_1m(),.inject_enable(),.injected(),
        .ram_ready(ready_sync[1]),.ram_idle(!active),.ram_fault(fault_sync[1]),
        .panel_ready(1'b1),.overflow(1'b0),.device_id(24'h515350),
        .pc({31'd0,FLASH_QSPI!=0}),.frames(cycles),.flash_misses(misses),
        .physical(7'd0),.keys(10'd0),.mem_req(request),.mem_read(read),
        .mem_addr(address),.mem_wdata(),.mem_be(),.mem_done(done||(request&&!read)),
        .mem_rdata(data),.busy(busy),.error(),.last_sequence());
    gba_flash #(.QSPI(FLASH_QSPI),.CLOCK_CYCLES(FLASH_CYCLES),.RX_REGISTER(FLASH_RX_REGISTER)) cartridge(.clk(clk),.clk_flash(clk_flash),
        .reset(reader_reset),.request(request&&read),.address({4'd0,address[22:2]}),
        .done(done),.data(data),.second_data(second),.misses(misses),
        .flash_clk(sck),.flash_cs_n(flash_cs_n),.flash_mosi(mosi_out),
        .flash_miso(flash_miso),.quad_other({flash_io3,flash_io2,flash_mosi}),
        .mosi_oe(oe),.quad_ready(qready),.quad_fault(qfault));
    assign flash_mosi=oe?mosi_out:1'bz;
    USRMCLK clock_out(.USRMCLKI(sck),.USRMCLKTS(1'b0));
    assign led={fault_sync[1],FLASH_QSPI!=0,4'd0,ready_sync[1],active};
endmodule
