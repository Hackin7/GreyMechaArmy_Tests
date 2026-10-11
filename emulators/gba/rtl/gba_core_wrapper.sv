`default_nettype none
module gba_core_wrapper (
 input wire clk_100, input wire reset_n,
 input wire pause, video_ready,
 input wire key_a,key_b,key_select,key_start,key_right,key_left,key_up,key_down,key_r,key_l,
 input wire [24:0] max_rom_addr, input wire flash_1m,
 output wire rom_read, output wire [24:0] rom_addr,
 input wire rom_done, input wire [31:0] rom_data,rom_second_data,
 output wire [31:0] ext_write_data, input wire [31:0] ext_read_data,
 output wire [25:0] ext_addr, output wire ext_read_not_write,ext_request, input wire ext_done,
 output wire vram_request,vram_read,output wire [13:0] vram_addr,
 output wire [31:0] vram_wdata,output wire [3:0] vram_be,
 input wire [31:0] vram_rdata,input wire vram_done,
 input wire [11:0] bios_wraddr, input wire [31:0] bios_wrdata, input wire bios_wr,
 output wire [7:0] pixel_x,pixel_y, output wire [15:0] pixel_addr,
 output wire [17:0] pixel_data, output wire pixel_we,
 output wire [15:0] audio_left,audio_right, output wire [31:0] debug_cpu_pc
);
 wire [31:0] unused32a,unused32b,unused32c,unused32d,unused32e,unused32f;
 wire [41:0] unused42; wire [63:0] unused64; wire [25:0] unused26;
 wire [7:0] unused8; wire unused0,unused1,unused2,unused3,unused4,unused5,unused6;
 wire unused7,unused8w,unused9,unused10,unused11,unused12,unused13,unused14,unused15;
 gba_top core (
  .clk100(clk_100), .video_ready(video_ready), .GBA_on(reset_n), .GBA_lockspeed(1'b1),
  .GBA_stable_ff_video(1'b1), .GBA_cputurbo(1'b0), .GBA_flash_1m(flash_1m),
  .CyclePrecalc(16'd100), .Underclock(2'b00), .MaxPakAddr(max_rom_addr),
  .CyclesMissing(unused32a), .CyclesVsyncSpeed(unused32b),
  .SramFlashEnable(1'b1), .memory_remap(1'b0), .increaseSSHeaderCount(1'b0),
  .save_state(1'b0), .load_state(1'b0), .maxpixels(1'b0), .specialmodule(1'b0),
  .savestate_number(32'd0), .RTC_timestampNew(1'b0), .RTC_timestampIn(32'd0),
  .RTC_timestampSaved(32'd0), .RTC_savedtimeIn(42'd0), .RTC_saveLoaded(1'b0),
  .RTC_timestampOut(unused32c), .RTC_savedtimeOut(unused42), .RTC_inuse(unused0),
  .sdram_read_ena(rom_read), .sdram_read_done(rom_done), .sdram_read_addr(rom_addr),
  .sdram_read_data(rom_data), .sdram_second_dword(rom_second_data),
  .bus_out_Din(ext_write_data), .bus_out_Dout(ext_read_data), .bus_out_Adr(ext_addr),
  .bus_out_rnw(ext_read_not_write), .bus_out_ena(ext_request), .bus_out_done(ext_done),
  .VRAM_Ext_req(vram_request), .VRAM_Ext_read(vram_read), .VRAM_Ext_addr(vram_addr),
  .VRAM_Ext_wdata(vram_wdata), .VRAM_Ext_be(vram_be),
  .VRAM_Ext_rdata(vram_rdata), .VRAM_Ext_done(vram_done),
  .SAVE_out_Din(unused64), .SAVE_out_Dout(64'd0), .SAVE_out_Adr(unused26),
  .SAVE_out_rnw(unused1), .SAVE_out_ena(unused2), .SAVE_out_active(unused3),
  .SAVE_out_be(unused8), .SAVE_out_done(1'b0),
  .bios_wraddr(bios_wraddr), .bios_wrdata(bios_wrdata), .bios_wr(bios_wr),
  .save_eeprom(unused4), .save_sram(unused5), .save_flash(unused6),
  .load_done(unused7), .savestate_busy(unused8w), .sleep_external(pause),
  .KeyA(key_a), .KeyB(key_b), .KeySelect(key_select), .KeyStart(key_start),
  .KeyRight(key_right), .KeyLeft(key_left), .KeyUp(key_up), .KeyDown(key_down),
  .KeyR(key_r), .KeyL(key_l),
  .serial_data_out(unused9), .serial_data_in(1'b1), .serial_clk_out(unused10),
  .serial_clk_in(1'b1), .serial_int_clock(unused11), .serial_sd_out(unused12),
  .serial_sd_in(1'b1), .serial_sd_dir(unused13), .serial_sc_out(unused14),
  .serial_sc_in(1'b1), .serial_sc_dir(unused15),
  .GBA_BusAddr(28'd0), .GBA_BusRnW(1'b0), .GBA_BusACC(2'b00),
  .GBA_BusWriteData(32'd0), .GBA_BusReadData(unused32d), .GBA_Bus_written(1'b0),
  .pixel_out_x(pixel_x), .pixel_out_y(pixel_y), .pixel_out_addr(pixel_addr),
  .pixel_out_data(pixel_data), .pixel_out_we(pixel_we),
  .sound_out_left(audio_left), .sound_out_right(audio_right),
  .debug_cpu_pc(debug_cpu_pc), .debug_cpu_mixed(unused32e),
  .debug_irq(unused32f), .debug_dma(), .debug_mem()
 );
endmodule
`default_nettype wire
