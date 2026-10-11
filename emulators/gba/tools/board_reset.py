"""Specialize the unused savestate engine for the board wrapper's constant pins.

The wrapper ties both save and load low. Its only reachable duties are the
power-up/falling-GBA_on reset sequence. Explicitly retaining just that sequence
lets synthesis discard the unreachable savestate transfers and their shadow
registers. This does not alter battery SRAM/flash/EEPROM support.
"""
import re


def reset_only(source):
    header = re.split(r'architecture\s+arch\s+of\s+gba_savestates\s+is', source, flags=re.I)[0]
    return header + '''architecture board_reset of gba_savestates is
   signal tick : integer range 0 to 8 := 0;
   signal gb_on_1 : std_logic := '0';
begin
   load_done <= '0';
   savestate_busy <= '1' when tick < 8 else '0';
   loading_savestate <= '0'; saving_savestate <= '0'; sleep_savestate <= '0';
   SAVE_BusAddr <= (others => '0'); SAVE_BusRnW <= '0';
   SAVE_BusACC <= ACCESS_32BIT; SAVE_BusWriteData <= (others => '0'); SAVE_Bus_ena <= '0';
   bus_out_Din <= (others => '0'); bus_out_Adr <= (others => '0');
   bus_out_rnw <= '0'; bus_out_ena <= '0'; bus_out_active <= '0'; bus_out_be <= (others => '0');
   gb_bus.Din <= (others => '0'); gb_bus.Dout <= (others => '0');
   gb_bus.Adr <= (others => '0'); gb_bus.rnw <= '0'; gb_bus.ena <= '0';
   gb_bus.done <= '0'; gb_bus.acc <= "00"; gb_bus.bEna <= "0000"; gb_bus.rst <= '0';
   internal_bus_out.Din <= (others => '0'); internal_bus_out.Dout <= (others => '0');
   internal_bus_out.Adr <= (others => '0'); internal_bus_out.rnw <= '0';
   internal_bus_out.ena <= '0'; internal_bus_out.done <= '0';
   internal_bus_out.acc <= ACCESS_32BIT; internal_bus_out.bEna <= "1111";
   process(clk100) begin
      if rising_edge(clk100) then
         -- synthesis translate_off
         assert save = '0' and load = '0'
            report "board reset specialization requires disabled savestates" severity failure;
         -- synthesis translate_on
         gb_on_1 <= gb_on;
         reset <= '0'; internal_bus_out.rst <= '0';
         if tick = 0 then internal_bus_out.rst <= '1'; end if;
         if tick = 7 then reset <= '1'; end if;
         if tick < 8 then tick <= tick + 1; end if;
         if gb_on = '0' and gb_on_1 = '1' then tick <= 0; end if;
      end if;
   end process;
end architecture;
'''
