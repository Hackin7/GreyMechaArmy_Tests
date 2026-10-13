// Small board image for measuring the actual GBA arbiter/PHY independently
// of the expensive GBA placement. It overwrites all PSRAM, never cartridge flash.
module top #(parameter ASYNC_CLOCK=1, WORDS=2097152, RAM_CORE_DIV=20, RAM_CLK_DIV=8,
    WRITE_HALF=1, READ_HALF=WRITE_HALF, READ_FALLING=0, INIT_HALF=1,
    RAM_GAP=4, POWERUP_CYCLES=20000)(
    input wire [4:0] btn,input wire btn_grey_n,btn_red_n,
    input wire host_sck,host_mosi,host_cs_n,output wire host_miso,
    inout wire [5:0] pmod_j1,
    output wire flash_cs_n,flash_mosi,input wire flash_miso,
    output wire oled_scl,oled_sda,oled_dc,oled_cs,oled_rst,
    output wire [7:0] led,output wire buzzer,clock_ref
);
    wire osc,clk,clk_ram,clk_panel,locked;
    reg [15:0] reference_divider=0;
    always @(posedge clk)reference_divider<=reference_divider+1'b1;
    assign clock_ref=reference_divider[15]; // RP2350 GP12: core clock / 65536.
    OSCG #(.DIV(6)) oscillator(.OSC(osc));
    gba_pll #(.CORE_DIV(RAM_CORE_DIV),.FLASH_DIV(RAM_CLK_DIV)) clocks(.osc(osc),.reset(1'b0),.core_clk(clk),
        .panel_clk(clk_panel),.flash_clk(clk_ram),.locked(locked));
    reg [7:0] startup=0;
    always @(posedge clk)
        if(!locked)startup<=0;else if(!(&startup))startup<=startup+1'b1;
    wire reset=!(&startup);
    wire run,pause,reset_pulse;
    reg [5:0] reset_hold=0;
    always @(posedge clk)
        if(reset || reset_pulse)reset_hold<=63;
        else if(reset_hold!=0)reset_hold<=reset_hold-1'b1;
    wire ram_reset=reset || reset_hold!=0;
    wire [7:0] rx,tx;wire rv,tv,tr;
    gb_spi_phy phy(.clk(clk),.reset(reset),.spi_sck(host_sck),
        .spi_mosi(host_mosi),.spi_csn(host_cs_n),.spi_miso(host_miso),
        .rx_data(rx),.rx_valid(rv),.tx_data(tx),.tx_valid(tv),.tx_ready(tr));
    wire hrq,hrd,hdone,ready,idle,ram_fault;
    wire [22:0] ha;wire [31:0] hw,hq;wire [3:0] hb;wire [23:0] id;
    reg [2:0] state=0;
    reg [20:0] word_index=0;
    reg [31:0] write_cycles=0,read_cycles=0,errors=0;
    wire [3:0] phase=state==0 ? 0 : state<3 ? 1 : state<5 ? 2 : 3;
    wire [31:0] status_pc={phase,errors!=0,6'd0,word_index};
    gba_host host(.clk(clk),.reset(reset),.rx_data(rx),.rx_valid(rv),
        .tx_data(tx),.tx_valid(tv),.tx_ready(tr),.run(run),.pause(pause),
        .reset_pulse(reset_pulse),.max_rom_addr(),.flash_1m(),.inject_enable(),.injected(),
        .ram_ready(ready),.ram_idle(idle),.ram_fault(ram_fault),.panel_ready(1'b1),
        .overflow(1'b0),.device_id(id),.pc(status_pc),.frames(write_cycles),
        .flash_misses(read_cycles),.physical(7'd0),.keys(errors[9:0]),
        .mem_req(hrq),.mem_read(hrd),.mem_addr(ha),.mem_wdata(hw),.mem_be(hb),
        .mem_done(hdone),.mem_rdata(hq),.busy(),.error(),.last_sequence());
    wire cs,sck,cdone;wire [3:0] din,dout,oe;wire [31:0] cq;
    reg crq=0,crd=0;
    wire [31:0] pattern=32'ha55a6789 ^ {11'd0,word_index} ^ {word_index,11'd0};
    gba_psram #(.ASYNC_CLOCK(ASYNC_CLOCK),.HALF_PERIOD(WRITE_HALF),
        .READ_HALF_PERIOD(READ_HALF),.READ_FALLING(READ_FALLING),.INIT_HALF_PERIOD(INIT_HALF),
        .CS_GAP(RAM_GAP),.POWERUP_CYCLES(POWERUP_CYCLES)) ram(.clk(clk),.clk_ram(clk_ram),.reset(ram_reset),
        .core_req(crq),.core_read(crd),.core_addr({5'd0,word_index}),
        .core_wdata(pattern),.core_rdata(cq),.core_done(cdone),
        .host_req(hrq),.host_read(hrd),.host_addr(ha),.host_wdata(hw),.host_be(hb),
        .host_rdata(hq),.host_done(hdone),.video_req(1'b0),.video_read(1'b0),
        .video_addr(23'd0),.video_wdata(32'd0),.video_be(4'd0),.video_rdata(),.video_done(),
        .ready(ready),.device_id(id),.fault(ram_fault),.idle(idle),
        .cs_n(cs),.sck(sck),.dq_in(din),.dq_out(dout),.dq_oe(oe));
    assign pmod_j1[0]=cs;assign pmod_j1[3]=sck;
    assign din={pmod_j1[2],pmod_j1[5],pmod_j1[4],pmod_j1[1]};
    assign pmod_j1[1]=oe[0]?dout[0]:1'bz;assign pmod_j1[4]=oe[1]?dout[1]:1'bz;
    assign pmod_j1[5]=oe[2]?dout[2]:1'bz;assign pmod_j1[2]=oe[3]?dout[3]:1'bz;
    always @(posedge clk)begin
        crq<=0;
        if(ram_reset)begin
            state<=0;word_index<=0;write_cycles<=0;read_cycles<=0;errors<=0;crd<=0;
        end else begin
            if(state==1 || state==2)write_cycles<=write_cycles+1'b1;
            if(state==3 || state==4)read_cycles<=read_cycles+1'b1;
            case(state)
                0: if(run && ready)state<=1;
                1: if(!pause)begin crq<=1;crd<=0;state<=2;end
                2: if(cdone)begin
                    if(word_index==WORDS-1)begin word_index<=0;state<=3;end
                    else begin word_index<=word_index+1'b1;state<=1;end
                end
                3: if(!pause)begin crq<=1;crd<=1;state<=4;end
                4: if(cdone)begin
                    if(cq!=pattern)errors<=errors+1'b1;
                    if(word_index==WORDS-1)state<=5;
                    else begin word_index<=word_index+1'b1;state<=3;end
                end
                default: state<=5;
            endcase
        end
    end
    assign led={ram_fault,errors!=0,phase==3,phase==2,phase==1,ready,pause,run};
    assign flash_cs_n=1;assign flash_mosi=0;
    assign oled_scl=0;assign oled_sda=0;assign oled_dc=0;assign oled_cs=1;assign oled_rst=0;
    assign buzzer=0;
endmodule
