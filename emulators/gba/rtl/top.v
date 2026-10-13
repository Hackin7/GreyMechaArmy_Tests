module top #(parameter FLASH_QSPI=1, FLASH_CYCLES=2, FLASH_RX_REGISTER=0, PLL_CORE_DIV=26, PLL_FLASH_DIV=4, PSRAM_FAST_READ=0)(
    input wire [4:0] btn,input wire btn_grey_n,btn_red_n,
    input wire host_sck,host_mosi,host_cs_n,output wire host_miso,
    inout wire [5:0] pmod_j1,
    output wire flash_cs_n,inout wire flash_mosi,input wire flash_miso,flash_io2,flash_io3,
    output wire oled_scl,oled_sda,oled_dc,oled_cs,oled_rst,
    output wire [7:0] led,output wire buzzer
);
    wire osc,clk_core,clk_panel,clk_flash,clk_ram,locked,main_locked,quad_locked;
    OSCG #(.DIV(6)) oscillator(.OSC(osc));
    gba_pll #(.FLASH_DIV(PSRAM_FAST_READ?4:8)) clocks(.osc(osc),.reset(1'b0),.core_clk(clk_core),
        .panel_clk(clk_panel),.flash_clk(clk_ram),.locked(main_locked));
    generate if(FLASH_QSPI)begin: quad_clock
        gba_pll #(.CORE_DIV(PLL_CORE_DIV),.FLASH_DIV(PLL_FLASH_DIV)) clocks(
            .osc(osc),.reset(1'b0),.core_clk(),.panel_clk(),
            .flash_clk(clk_flash),.locked(quad_locked));
    end else begin: spi_clock
        assign clk_flash=clk_ram;assign quad_locked=1;
    end endgenerate
    assign locked=main_locked&&quad_locked;
    reg [7:0] startup=0;
    always @(posedge clk_core) begin
        if(!locked) startup<=0;else if(!(&startup)) startup<=startup+1'b1;
    end
    wire reset=!(&startup);
    wire run,pause,reset_pulse,inject_enable,flash_1m;
    wire [9:0] injected,keys;wire [6:0] physical;wire mode_toggle;
    wire [24:0] max_rom_addr;
    reg [5:0] reset_hold=0;
    always @(posedge clk_core) begin
        if(reset||reset_pulse) reset_hold<=63;
        else if(reset_hold!=0) reset_hold<=reset_hold-1'b1;
    end
    wire peripheral_reset=reset||(reset_hold!=0);
    wire core_reset=peripheral_reset||!run;
    (* async_reg="true" *) reg [1:0] panel_sync=0,lines_sync=0;
    always @(posedge clk_panel or posedge peripheral_reset) begin
        if(peripheral_reset) panel_sync<=0;else panel_sync<={panel_sync[0],1'b1};
    end
    always @(posedge clk_panel or posedge core_reset) begin
        if(core_reset) lines_sync<=0;else lines_sync<={lines_sync[0],1'b1};
    end
    gba_buttons #(.CLK_HZ(21000000)) buttons(.clk(clk_core),.reset(reset),.btn_n(btn),
        .grey_n(btn_grey_n),.red_n(btn_red_n),.inject_enable(inject_enable),
        .injected(injected),.keys(keys),.physical(physical),.mode_toggle(mode_toggle));
    wire [7:0] rx_data,tx_data;wire rx_valid,tx_valid,tx_ready;
    gb_spi_phy phy(.clk(clk_core),.reset(reset),.spi_sck(host_sck),
        .spi_mosi(host_mosi),.spi_csn(host_cs_n),.spi_miso(host_miso),
        .rx_data(rx_data),.rx_valid(rx_valid),.tx_data(tx_data),.tx_valid(tx_valid),.tx_ready(tx_ready));
    wire ram_ready,ram_idle,ram_fault,panel_ready,overflow,flash_ready,flash_fault;
    (* async_reg="true" *) reg [1:0] flash_ready_sync=0,flash_fault_sync=0;
    always @(posedge clk_core)begin
        flash_ready_sync<={flash_ready_sync[0],flash_ready};
        flash_fault_sync<={flash_fault_sync[0],flash_fault};
    end
    wire [23:0] device_id;wire [31:0] pc,frames,flash_misses;
    wire host_mem_req,host_mem_read,host_mem_done;
    wire [22:0] host_mem_addr;wire [31:0] host_mem_wdata,host_mem_rdata;
    wire [3:0] host_mem_be;wire host_busy;wire [7:0] host_error,last_sequence;
    gba_host host(.clk(clk_core),.reset(reset),.rx_data(rx_data),.rx_valid(rx_valid),
        .tx_data(tx_data),.tx_valid(tx_valid),.tx_ready(tx_ready),
        .run(run),.pause(pause),.reset_pulse(reset_pulse),.max_rom_addr(max_rom_addr),.flash_1m(flash_1m),
        .inject_enable(inject_enable),.injected(injected),.ram_ready(ram_ready&&flash_ready_sync[1]),.ram_idle(ram_idle),
        .ram_fault(ram_fault||flash_fault_sync[1]),.panel_ready(panel_ready),.overflow(overflow),.device_id(device_id),
        .pc(pc),.frames(frames),.flash_misses(flash_misses),.physical(physical),.keys(keys),
        .mem_req(host_mem_req),.mem_read(host_mem_read),.mem_addr(host_mem_addr),
        .mem_wdata(host_mem_wdata),.mem_be(host_mem_be),.mem_done(host_mem_done),.mem_rdata(host_mem_rdata),
        .busy(host_busy),.error(host_error),.last_sequence(last_sequence));
    wire ext_req,ext_read,ext_done;wire [25:0] ext_addr;wire [31:0] ext_wdata,ext_rdata;
    wire vram_req,vram_read,vram_done;wire [13:0] vram_addr;
    wire [31:0] vram_wdata,vram_rdata;wire [3:0] vram_be;
    wire ram_cs,ram_sck;wire [3:0] dq_in,dq_out,dq_oe;
    assign pmod_j1[0]=ram_cs;assign pmod_j1[3]=ram_sck;
    assign dq_in={pmod_j1[2],pmod_j1[5],pmod_j1[4],pmod_j1[1]};
    assign pmod_j1[1]=dq_oe[0] ? dq_out[0]:1'bz;
    assign pmod_j1[4]=dq_oe[1] ? dq_out[1]:1'bz;
    assign pmod_j1[5]=dq_oe[2] ? dq_out[2]:1'bz;
    assign pmod_j1[2]=dq_oe[3] ? dq_out[3]:1'bz;
    gba_psram #(.HALF_PERIOD(PSRAM_FAST_READ?2:1),.READ_HALF_PERIOD(1),
        .READ_FALLING(PSRAM_FAST_READ),.INIT_HALF_PERIOD(PSRAM_FAST_READ?2:1),
        .CS_GAP(PSRAM_FAST_READ?8:4),.POWERUP_CYCLES(PSRAM_FAST_READ?40000:20000),.ASYNC_CLOCK(1)) ram(.clk(clk_core),.clk_ram(clk_ram),.reset(peripheral_reset),
        .core_req(ext_req),.core_read(ext_read),.core_addr(ext_addr),.core_wdata(ext_wdata),
        .core_rdata(ext_rdata),.core_done(ext_done),.host_req(host_mem_req),.host_read(host_mem_read),
        .host_addr(host_mem_addr),.host_wdata(host_mem_wdata),.host_be(host_mem_be),
        .host_rdata(host_mem_rdata),.host_done(host_mem_done),.ready(ram_ready),.device_id(device_id),
        .video_req(vram_req),.video_read(vram_read),.video_addr({7'h10,vram_addr,2'b00}),
        .video_wdata(vram_wdata),.video_be(vram_be),.video_rdata(vram_rdata),.video_done(vram_done),
        .fault(ram_fault),.idle(ram_idle),.cs_n(ram_cs),.sck(ram_sck),.dq_in(dq_in),.dq_out(dq_out),.dq_oe(dq_oe));
    wire rom_read,rom_done;wire [24:0] rom_addr;wire [31:0] rom_data,rom_second;
    wire flash_clk_wire,flash_mosi_out,flash_mosi_oe;
    assign flash_mosi=flash_mosi_oe?flash_mosi_out:1'bz;
    gba_flash #(.QSPI(FLASH_QSPI),.CLOCK_CYCLES(FLASH_CYCLES),.RX_REGISTER(FLASH_RX_REGISTER)) cartridge(.clk(clk_core),.clk_flash(clk_flash),.reset(FLASH_QSPI?peripheral_reset:core_reset),
        .request(rom_read),.address(rom_addr),.done(rom_done),.data(rom_data),.second_data(rom_second),
        .flash_clk(flash_clk_wire),.flash_cs_n(flash_cs_n),.flash_mosi(flash_mosi_out),.mosi_oe(flash_mosi_oe),
        .quad_other({flash_io3,flash_io2,flash_mosi}),.quad_ready(flash_ready),.quad_fault(flash_fault),
        .flash_miso(flash_miso),.misses(flash_misses));
    USRMCLK flash_clock(.USRMCLKI(flash_clk_wire),.USRMCLKTS(1'b0));
    wire [7:0] pixel_x,pixel_y;wire [15:0] pixel_addr;wire [17:0] pixel_data;
    wire pixel_we,video_ready;wire [15:0] audio_left,audio_right;
    gba_core_wrapper gba(.clk_100(clk_core),.reset_n(!core_reset),.pause(pause),.video_ready(video_ready),
        .key_a(keys[0]),.key_b(keys[1]),.key_select(keys[2]),.key_start(keys[3]),
        .key_right(keys[4]),.key_left(keys[5]),.key_up(keys[6]),.key_down(keys[7]),.key_r(keys[8]),.key_l(keys[9]),
        .max_rom_addr(max_rom_addr),.flash_1m(flash_1m),.rom_read(rom_read),.rom_addr(rom_addr),
        .rom_done(rom_done),.rom_data(rom_data),.rom_second_data(rom_second),.ext_write_data(ext_wdata),
        .ext_read_data(ext_rdata),.ext_addr(ext_addr),.ext_read_not_write(ext_read),.ext_request(ext_req),.ext_done(ext_done),
        .vram_request(vram_req),.vram_read(vram_read),.vram_addr(vram_addr),
        .vram_wdata(vram_wdata),.vram_be(vram_be),.vram_rdata(vram_rdata),.vram_done(vram_done),
        .bios_wraddr(12'd0),.bios_wrdata(32'd0),.bios_wr(1'b0),.pixel_x(pixel_x),.pixel_y(pixel_y),
        .pixel_addr(pixel_addr),.pixel_data(pixel_data),.pixel_we(pixel_we),
        .audio_left(audio_left),.audio_right(audio_right),.debug_cpu_pc(pc));
    wire line_ready,line_fitted,line_done;wire [7:0] line_number,rd_addr;wire [15:0] rd_data;
    gba_lines lines(.core_clk(clk_core),.core_reset(core_reset),.pixel_we(pixel_we),
        .pixel_x(pixel_x),.pixel_y(pixel_y),.pixel_data(pixel_data),.mode_toggle(mode_toggle),
        .video_ready(video_ready),.overflow(overflow),.captured_frames(frames),
        .panel_clk(clk_panel),.panel_reset(!lines_sync[1]),.rd_addr(rd_addr),.rd_data(rd_data),
        .line_ready(line_ready),.line_number(line_number),.line_fitted(line_fitted),.line_done(line_done));
    wire initialized;wire [31:0] displayed_frames;
    reg panel_s1,panel_s2;
    always @(posedge clk_core) begin panel_s1<=initialized;panel_s2<=panel_s1;end
    assign panel_ready=panel_s2;
    gba_display display(.clk(clk_panel),.resetn(panel_sync[1]),
        .line_ready(line_ready),.line_fitted(line_fitted),.line_number(line_number),.line_done(line_done),
        .rd_addr(rd_addr),.rd_data(rd_data),.initialized(initialized),.displayed_frames(displayed_frames),
        .sclk(oled_scl),.mosi(oled_sda),.dc(oled_dc),.cs_n(oled_cs),.rst_n(oled_rst));
    assign led={overflow,(ram_fault||flash_fault_sync[1]),host_error!=0,frames[0],panel_ready,ram_ready,pause,run};
    assign buzzer=1'b0;
endmodule
