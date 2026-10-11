library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.pProc_bus_gba.all;
entity tb_gba_board_reset is end;
architecture sim of tb_gba_board_reset is
  signal clk : std_logic := '0';
  signal gb_on : std_logic := '0';
  signal bus_in : proc_bus_gb_type := ((others=>'0'),(others=>'0'),(others=>'0'),'0','0','0',"00","0000",'0');
  type buses_t is array(0 to 1) of proc_bus_gb_type;
  signal internal_drive, mmio_drive : buses_t;
  signal reset, busy : std_logic_vector(0 to 1);
begin
  clk <= not clk after 5 ns;
dut0: entity work.gba_savestates_reference generic map (Softmap_GBA_WRam_ADDR=>0,Softmap_GBA_FLASH_ADDR=>131072,Softmap_GBA_EEPROM_ADDR=>98304,is_simu=>'1') port map (
clk100 => clk,
gb_on => gb_on,
reset => reset(0),
load_done => open,
increaseSSHeaderCount => '0',
save => '0',
load => '0',
savestate_address => 0,
savestate_busy => busy(0),
cpu_jump => '0',
internal_bus_out => bus_in,
loading_savestate => open,
saving_savestate => open,
sleep_savestate => open,
bus_ena_in => '0',
gb_bus => bus_in,
SAVE_BusAddr => open,
SAVE_BusRnW => open,
SAVE_BusACC => open,
SAVE_BusWriteData => open,
SAVE_Bus_ena => open,
SAVE_BusReadData => (others=>'0'),
SAVE_BusReadDone => '0',
bus_out_Din => open,
bus_out_Dout => (others=>'0'),
bus_out_Adr => open,
bus_out_rnw => open,
bus_out_ena => open,
bus_out_active => open,
bus_out_be => open,
bus_out_done => '0',
internal_bus_out_drive => internal_drive(0),
gb_bus_drive => mmio_drive(0)
);
dut1: entity work.gba_savestates generic map (Softmap_GBA_WRam_ADDR=>0,Softmap_GBA_FLASH_ADDR=>131072,Softmap_GBA_EEPROM_ADDR=>98304,is_simu=>'1') port map (
clk100 => clk,
gb_on => gb_on,
reset => reset(1),
load_done => open,
increaseSSHeaderCount => '0',
save => '0',
load => '0',
savestate_address => 0,
savestate_busy => busy(1),
cpu_jump => '0',
internal_bus_out => bus_in,
loading_savestate => open,
saving_savestate => open,
sleep_savestate => open,
bus_ena_in => '0',
gb_bus => bus_in,
SAVE_BusAddr => open,
SAVE_BusRnW => open,
SAVE_BusACC => open,
SAVE_BusWriteData => open,
SAVE_Bus_ena => open,
SAVE_BusReadData => (others=>'0'),
SAVE_BusReadDone => '0',
bus_out_Din => open,
bus_out_Dout => (others=>'0'),
bus_out_Adr => open,
bus_out_rnw => open,
bus_out_ena => open,
bus_out_active => open,
bus_out_be => open,
bus_out_done => '0',
internal_bus_out_drive => internal_drive(1),
gb_bus_drive => mmio_drive(1)
);
  process begin
    -- Host packets take many more than eight core clocks. Compare the complete
    -- startup and repeated run/stop/reset sequence under that actual contract.
    wait for 200 ns; gb_on<='1'; wait for 1000 ns; gb_on<='0';
    wait for 200 ns; gb_on<='1'; wait for 600 ns; gb_on<='0';
    wait for 1000 ns; gb_on<='1'; wait for 1000 ns;
    report "PASS board reset: startup and repeated GBA_on reset pulses match upstream";
    finish;
  end process;
  process begin
    wait until falling_edge(clk);
    assert reset(0)=reset(1) report "reset pulse differs from upstream" severity failure;
    assert busy(0)=busy(1) report "reset readiness differs from upstream" severity failure;
    assert internal_drive(0).rst=internal_drive(1).rst
      report "savestate default-register reset differs from upstream" severity failure;
  end process;
end;
