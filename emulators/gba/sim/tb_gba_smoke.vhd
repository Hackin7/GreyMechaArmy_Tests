library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_gba_smoke is
end entity;

architecture sim of tb_gba_smoke is
  type bios_t is array (0 to 15) of std_logic_vector(31 downto 0);
  constant smoke_bios : bios_t := (
    x"E59F0028", x"E59F1028", x"E5801000", x"E59F0024",
    x"E59F1024", x"E5801000", x"E59F0010", x"E59F1010",
    x"E5801000", x"EAFFFFFE", x"E1A00000", x"E1A00000",
    x"060007D0", x"0000001F", x"04000000", x"00000403"
  );

  signal clk                 : std_logic := '0';
  signal gba_on              : std_logic := '0';
  signal bios_wraddr         : std_logic_vector(11 downto 0) := (others => '0');
  signal bios_wrdata         : std_logic_vector(31 downto 0) := (others => '0');
  signal bios_wr             : std_logic := '0';
  signal rom_ena             : std_logic;
  signal rom_done            : std_logic := '0';
  signal rom_addr            : std_logic_vector(24 downto 0);
  signal rom_data            : std_logic_vector(31 downto 0) := (others => '0');
  signal rom_second          : std_logic_vector(31 downto 0) := (others => '0');
  signal ext_write_data      : std_logic_vector(31 downto 0);
  signal ext_read_data       : std_logic_vector(31 downto 0) := (others => '0');
  signal ext_addr            : std_logic_vector(25 downto 0);
  signal ext_rnw             : std_logic;
  signal ext_ena             : std_logic;
  signal ext_done            : std_logic := '0';
  signal pixel_x             : integer range 0 to 239;
  signal pixel_y             : integer range 0 to 159;
  signal pixel_addr          : integer range 0 to 38399;
  signal pixel_data          : std_logic_vector(17 downto 0);
  signal pixel_we            : std_logic;
  signal debug_pc            : std_logic_vector(31 downto 0);
  signal debug_bus_addr      : std_logic_vector(27 downto 0) := (others => '0');
  signal debug_bus_rnw       : std_logic := '0';
  signal debug_bus_acc       : std_logic_vector(1 downto 0) := "00";
  signal debug_bus_write     : std_logic_vector(31 downto 0) := (others => '0');
  signal debug_bus_read      : std_logic_vector(31 downto 0);
  signal debug_bus_written   : std_logic := '0';
  signal config_verified     : std_logic := '0';
begin
  clk <= not clk after 5 ns;

  dut : entity work.gba_top
    generic map (
      Softmap_GBA_Gamerom_ADDR => 0,
      Softmap_GBA_WRam_ADDR    => 131072,
      Softmap_GBA_FLASH_ADDR   => 0,
      Softmap_GBA_EEPROM_ADDR  => 0,
      Softmap_SaveState_ADDR   => 0,
      is_simu                  => '1',
      turbosound               => '0'
    )
    port map (
      clk100 => clk, GBA_on => gba_on, GBA_lockspeed => '0',
      GBA_stable_ff_video => '1', GBA_cputurbo => '1', GBA_flash_1m => '0',
      CyclePrecalc => std_logic_vector(to_unsigned(100, 16)), Underclock => "00",
      MaxPakAddr => (others => '0'), CyclesMissing => open, CyclesVsyncSpeed => open,
      SramFlashEnable => '1', memory_remap => '0', increaseSSHeaderCount => '0',
      save_state => '0', load_state => '0', maxpixels => '0', specialmodule => '0',
      savestate_number => 0, RTC_timestampNew => '0', RTC_timestampIn => (others => '0'),
      RTC_timestampSaved => (others => '0'), RTC_savedtimeIn => (others => '0'),
      RTC_saveLoaded => '0', RTC_timestampOut => open, RTC_savedtimeOut => open,
      RTC_inuse => open, sdram_read_ena => rom_ena, sdram_read_done => rom_done,
      sdram_read_addr => rom_addr, sdram_read_data => rom_data,
      sdram_second_dword => rom_second, bus_out_Din => ext_write_data,
      bus_out_Dout => ext_read_data, bus_out_Adr => ext_addr, bus_out_rnw => ext_rnw,
      bus_out_ena => ext_ena, bus_out_done => ext_done, SAVE_out_Din => open,
      SAVE_out_Dout => (others => '0'), SAVE_out_Adr => open, SAVE_out_rnw => open,
      SAVE_out_ena => open, SAVE_out_active => open, SAVE_out_be => open,
      SAVE_out_done => '0', bios_wraddr => bios_wraddr, bios_wrdata => bios_wrdata,
      bios_wr => bios_wr, save_eeprom => open, save_sram => open, save_flash => open,
      load_done => open, savestate_busy => open, sleep_external => '0',
      KeyA => '0', KeyB => '0', KeySelect => '0', KeyStart => '0', KeyRight => '0',
      KeyLeft => '0', KeyUp => '0', KeyDown => '0', KeyR => '0', KeyL => '0',
      serial_data_out => open, serial_data_in => '1', serial_clk_out => open,
      serial_clk_in => '1', serial_int_clock => open, serial_sd_out => open,
      serial_sd_in => '1', serial_sd_dir => open, serial_sc_out => open,
      serial_sc_in => '1', serial_sc_dir => open, GBA_BusAddr => debug_bus_addr,
      GBA_BusRnW => debug_bus_rnw, GBA_BusACC => debug_bus_acc,
      GBA_BusWriteData => debug_bus_write, GBA_BusReadData => debug_bus_read,
      GBA_Bus_written => debug_bus_written, pixel_out_x => pixel_x,
      pixel_out_y => pixel_y, pixel_out_addr => pixel_addr, pixel_out_data => pixel_data,
      pixel_out_we => pixel_we, sound_out_left => open, sound_out_right => open,
      debug_cpu_pc => debug_pc, debug_cpu_mixed => open, debug_irq => open,
      debug_dma => open, debug_mem => open
    );

  memory_model : process(clk)
  begin
    if rising_edge(clk) then
      rom_done <= '0';
      ext_done <= '0';
      if rom_ena = '1' then
        rom_data <= (others => '0');
        rom_second <= (others => '0');
        rom_done <= '1';
      end if;
      if ext_ena = '1' then
        if ext_rnw = '1' then
          ext_read_data <= (others => '0');
        end if;
        ext_done <= '1';
      end if;
    end if;
  end process;

  stimulus : process
  begin
    wait for 80 ns;
    for i in smoke_bios'range loop
      bios_wraddr <= std_logic_vector(to_unsigned(i, bios_wraddr'length));
      bios_wrdata <= smoke_bios(i);
      bios_wr <= '1';
      wait until rising_edge(clk);
    end loop;
    bios_wr <= '0';
    wait for 80 ns;
    gba_on <= '1';
    wait for 100 us;
    debug_bus_addr <= x"4000000";
    debug_bus_rnw <= '1';
    debug_bus_acc <= "01";
    debug_bus_written <= '1';
    wait until rising_edge(clk);
    debug_bus_written <= '0';
    wait for 2 us;
    report "debug DISPCNT word=" & to_hstring(debug_bus_read) severity note;
    assert debug_bus_read(15 downto 0) = x"0403"
      report "DISPCNT readback mismatch" severity failure;
    debug_bus_addr <= x"60007D0";
    debug_bus_acc <= "10";
    debug_bus_written <= '1';
    wait until rising_edge(clk);
    debug_bus_written <= '0';
    wait for 2 us;
    report "debug VRAM[1000] word=" & to_hstring(debug_bus_read) severity note;
    assert debug_bus_read = x"0000001F"
      report "VRAM readback mismatch" severity failure;
    config_verified <= '1';
    wait;
  end process;

  monitor : process(clk)
    variable cycles : natural := 0;
  begin
    if rising_edge(clk) and gba_on = '1' then
      cycles := cycles + 1;
      if config_verified = '1' and pixel_we = '1' and pixel_addr >= 1000 then
        report "PASS: ARM BIOS executed, MMIO/VRAM matched, and PPU scanned after " &
               integer'image(cycles) & " cycles" severity note;
        finish;
      elsif cycles mod 100000 = 0 then
        report "progress cycles=" & integer'image(cycles) &
               " pc=" & to_hstring(debug_pc) &
               " pixel=" & to_hstring(pixel_data) &
               " addr=" & integer'image(pixel_addr) severity note;
      end if;
      if cycles = 2000000 then
        report "FAIL timeout pc=" & to_hstring(debug_pc) &
               " pixel=" & to_hstring(pixel_data) &
               " addr=" & integer'image(pixel_addr) severity failure;
      end if;
    end if;
  end process;
end architecture;
