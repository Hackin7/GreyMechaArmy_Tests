library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.pProc_bus_gba.all;

-- Pixel-for-pixel comparison of the shared board renderer against the original
-- parallel engines. Covers every display mode with all applicable backgrounds,
-- distinct scroll/affine transforms, mosaic, OBJ, windows and alpha blending.
entity tb_gba_renderer is
  generic(ExternalMemory : boolean := false);
end;
architecture sim of tb_gba_renderer is
  signal clk : std_logic := '0';
  signal bus_in : proc_bus_gb_type := ((others=>'0'), (others=>'0'), (others=>'0'), '0','0','0',"10","1111",'0');
  type buses_t is array(0 to 1) of proc_bus_gb_type;
  signal responses : buses_t;
  type ints_t is array(0 to 1) of integer;
  type xints_t is array(0 to 1) of integer range 0 to 239;
  type yints_t is array(0 to 1) of integer range 0 to 159;
  type aints_t is array(0 to 1) of integer range 0 to 38399;
  signal px : xints_t;
  signal py : yints_t;
  signal pa : aints_t;
  type colors_t is array(0 to 1) of std_logic_vector(14 downto 0);
  signal color : colors_t;
  signal we, ready : std_logic_vector(0 to 1);
  signal line : unsigned(7 downto 0) := (others=>'0');
  signal draw, hb, vb, lt, refupdate : std_logic := '0';
  signal low_addr : integer range 0 to 16383 := 0;
  signal high_addr : integer range 0 to 8191 := 0;
  signal small_addr : integer range 0 to 127 := 0;
  signal oam_addr : integer range 0 to 255 := 0;
  signal data : std_logic_vector(31 downto 0) := (others=>'0');
  signal low_we, high_we : std_logic := '0';
  signal palette_we, oam_we : std_logic_vector(3 downto 0) := "0000";
  type line_t is array(0 to 239) of std_logic_vector(14 downto 0);
  type image_t is array(0 to 1) of line_t;
  signal pixels : image_t;
  signal count : ints_t := (0,0);
  signal clear_count : std_logic := '0';
  signal dut_low_we, ext_req, ext_read, ext_done : std_logic := '0';
  signal ext_addr : std_logic_vector(13 downto 0);
  signal ext_data, ext_wdata : std_logic_vector(31 downto 0) := (others => '0');
  signal ext_be : std_logic_vector(3 downto 0);
  type vram_t is array(0 to 16383) of std_logic_vector(31 downto 0);
  signal vram : vram_t := (others => (others => '0'));
begin
  clk <= not clk after 5 ns;
  dut_low_we <= low_we when not ExternalMemory else '0';
  process(clk)
    variable remaining : natural := 0;
    variable held_addr : natural := 0;
  begin
    if rising_edge(clk) then
      ext_done <= '0';
      if low_we = '1' then vram(low_addr) <= data; end if;
      if ext_req = '1' then
        assert remaining = 0 report "Overlapping renderer VRAM reads" severity failure;
        assert ext_read = '1' report "Unexpected renderer CPU write" severity failure;
        held_addr := to_integer(unsigned(ext_addr));
        remaining := 4 + held_addr mod 17;
      elsif remaining > 0 then
        remaining := remaining - 1;
        if remaining = 0 then ext_data <= vram(held_addr); ext_done <= '1'; end if;
      end if;
    end if;
  end process;
dut0: entity work.gba_gpu_drawer_reference generic map (is_simu => '1') port map (
clk100 => clk,
gb_bus => bus_in,
lockspeed => '0',
maxpixels => '0',
bitmapdrawmode => open,
vram_block_mode => open,
pixel_out_x => px(0),
pixel_out_y => py(0),
pixel_out_addr => pa(0),
pixel_out_data => color(0),
pixel_out_we => we(0),
drawer_ready => ready(0),
linecounter => line,
pixelpos => 511,
drawline => draw,
refpoint_update => refupdate,
hblank_trigger => hb,
vblank_trigger => vb,
line_trigger => lt,
newline_invsync => '0',
VRAM_Lo_addr => low_addr,
VRAM_Lo_datain => data,
VRAM_Lo_dataout => open,
VRAM_Lo_we => low_we,
VRAM_Lo_be => "1111",
VRAM_Hi_addr => high_addr,
VRAM_Hi_datain => data,
VRAM_Hi_dataout => open,
VRAM_Hi_we => high_we,
VRAM_Hi_be => "1111",
OAMRAM_PROC_addr => oam_addr,
OAMRAM_PROC_datain => data,
OAMRAM_PROC_dataout => open,
OAMRAM_PROC_we => oam_we,
PALETTE_BG_addr => small_addr,
PALETTE_BG_datain => data,
PALETTE_BG_dataout => open,
PALETTE_BG_we => palette_we,
PALETTE_OAM_addr => small_addr,
PALETTE_OAM_datain => data,
PALETTE_OAM_dataout => open,
PALETTE_OAM_we => palette_we,
gb_bus_drive => responses(0)
);
dut1: entity work.gba_gpu_drawer generic map (is_simu => '1', ExternalVRAMLow => ExternalMemory) port map (
clk100 => clk,
gb_bus => bus_in,
lockspeed => '0',
maxpixels => '0',
bitmapdrawmode => open,
vram_block_mode => open,
pixel_out_x => px(1),
pixel_out_y => py(1),
pixel_out_addr => pa(1),
pixel_out_data => color(1),
pixel_out_we => we(1),
drawer_ready => ready(1),
linecounter => line,
pixelpos => 511,
drawline => draw,
refpoint_update => refupdate,
hblank_trigger => hb,
vblank_trigger => vb,
line_trigger => lt,
newline_invsync => '0',
VRAM_Lo_addr => low_addr,
VRAM_Lo_datain => data,
VRAM_Lo_dataout => open,
VRAM_Lo_we => dut_low_we,
VRAM_Lo_be => "1111",
VRAM_Ext_req => ext_req, VRAM_Ext_read => ext_read, VRAM_Ext_addr => ext_addr,
VRAM_Ext_wdata => ext_wdata, VRAM_Ext_be => ext_be,
VRAM_Ext_rdata => ext_data, VRAM_Ext_done => ext_done,
VRAM_Hi_addr => high_addr,
VRAM_Hi_datain => data,
VRAM_Hi_dataout => open,
VRAM_Hi_we => high_we,
VRAM_Hi_be => "1111",
OAMRAM_PROC_addr => oam_addr,
OAMRAM_PROC_datain => data,
OAMRAM_PROC_dataout => open,
OAMRAM_PROC_we => oam_we,
PALETTE_BG_addr => small_addr,
PALETTE_BG_datain => data,
PALETTE_BG_dataout => open,
PALETTE_BG_we => palette_we,
PALETTE_OAM_addr => small_addr,
PALETTE_OAM_datain => data,
PALETTE_OAM_dataout => open,
PALETTE_OAM_we => palette_we,
gb_bus_drive => responses(1)
);
  process(clk) begin if rising_edge(clk) then
    for i in 0 to 1 loop
      if clear_count='1' then count(i)<=0;
      elsif we(i)='1' then
        assert count(i)<240 report "duplicate renderer pixel" severity failure;
        pixels(i)(px(i))<=color(i); count(i)<=count(i)+1;
      end if;
    end loop;
  end if; end process;
  process
    procedure step(n : positive := 1) is begin
      for i in 1 to n loop wait until falling_edge(clk); end loop;
    end;
    procedure regwrite(address : natural; value : std_logic_vector(31 downto 0)) is begin
      -- The internal MMIO bus uses offsets; the memory mux strips 0x04000000.
      bus_in.Adr <= std_logic_vector(to_unsigned(address mod 16#04000000#,28));
      bus_in.Din <= value; bus_in.ena <= '1'; step(2); bus_in.ena <= '0'; step(2);
    end;
    procedure sprites(base : natural) is
      variable attr0, attr1, attr2, affine : natural;
    begin
      oam_we<="1111";
    for obj in 0 to 11 loop
      attr0 := base + (obj*3) mod 14 + (obj mod 3)*1024;
      attr1 := (obj*5) mod 40 + 3*16384; -- 64x64, spanning later test rows
      if obj mod 4=0 then
        attr0 := attr0 + 256; -- affine matrix 0
      else
        attr1 := attr1 + (obj mod 2)*4096 + ((obj/2) mod 2)*8192;
      end if;
      if obj mod 2=1 then attr0 := attr0 + 4096; end if;
      attr2 := 16#200# + obj*4 + (obj mod 4)*1024 + (obj mod 16)*4096;
      -- Matrix 0 occupies attr3 of objects 0..3 (dx, dmx, dy, dmy).
      case obj is
        when 0 | 3 => affine := 16#0100#;
        when 1 => affine := 16#0040#;
        when 2 => affine := 16#FFC0#;
        when others => affine := 0;
      end case;
      oam_addr<=obj*2;
      data<=std_logic_vector(to_unsigned(attr1,16)) & std_logic_vector(to_unsigned(attr0,16)); step;
      oam_addr<=obj*2+1;
      data<=std_logic_vector(to_unsigned(affine,16)) & std_logic_vector(to_unsigned(attr2,16)); step;
    end loop;
    oam_we<="0000";
    end;
    variable value : unsigned(31 downto 0);
    variable timeout : natural;
    variable coefficient : natural;
  begin
    bus_in.rst<='1'; step(2); bus_in.rst<='0'; step(2);
    low_we<='1'; high_we<='1';
    for i in 0 to 16383 loop
      low_addr<=i; high_addr<=i mod 8192;
      data<=std_logic_vector(to_unsigned((i*73+12345) mod 65536,16)) &
            std_logic_vector(to_unsigned((i*119+23456) mod 65536,16)); step;
    end loop;
    low_we<='0'; high_we<='0'; palette_we<="1111";
    for i in 0 to 127 loop
      small_addr<=i;
      data<=std_logic_vector(to_unsigned((i*137+91) mod 32768,16)) &
            std_logic_vector(to_unsigned((i*243+17) mod 32768,16)); step;
    end loop;
    palette_we<="0000"; oam_we<="1111";
    for i in 0 to 255 loop
      oam_addr<=i;
      if i mod 2=0 then data<=x"00000200"; else data<=x"00000000"; end if; step;
    end loop;
    -- Overlap twelve sprites to exercise priority/coverage read-after-write,
    -- transparent texels, affine transforms, flips, mosaic and OBJ windows.
    sprites(0);
    for scene in 0 to 23 loop
      vb<='1'; step; vb<='0'; step(4);
      if scene=12 or scene=18 then sprites(scene*6); end if;
      -- Same modes with an additional mosaic/window/blend configuration.
      regwrite(16#04000008#, x"04810100");
      regwrite(16#0400000C#, x"CC8B880A");
      regwrite(16#04000010#, x"00030005"); regwrite(16#04000014#, x"0007000B");
      regwrite(16#04000018#, x"000D0011"); regwrite(16#0400001C#, x"00130017");
      regwrite(16#04000020#, x"000000D0"); regwrite(16#04000024#, x"01000020");
      regwrite(16#04000028#, x"00000800"); regwrite(16#0400002C#, x"00000400");
      regwrite(16#04000030#, x"0010FF00"); regwrite(16#04000034#, x"00E00030");
      regwrite(16#04000038#, x"00005000"); regwrite(16#0400003C#, x"00003000");
      regwrite(16#04000040#, x"20B010D0"); regwrite(16#04000044#, x"00800080");
      regwrite(16#04000048#, x"3F3F3F3F");
      if scene>=6 then
        regwrite(16#0400004C#, x"00003232");
        if scene>=18 then regwrite(16#04000050#, x"1F103FFF"); -- darken
        elsif scene>=12 then regwrite(16#04000050#, x"1F103FBF"); -- brighten
        else regwrite(16#04000050#, x"08083F7F"); end if; -- alpha
      else
        regwrite(16#0400004C#, x"00000000"); regwrite(16#04000050#, x"00000000");
      end if;
      value:=to_unsigned(16#1F00#+scene mod 6,32);
      if scene>=6 then value:=value or to_unsigned(16#E000#,32); end if;
      regwrite(16#04000000#,std_logic_vector(value));
      for i in 0 to 1 loop
        assert responses(i).Dout(15 downto 0)=std_logic_vector(value(15 downto 0))
          report "renderer configuration write did not take effect" severity failure;
      end loop;
      refupdate<='1'; step; refupdate<='0';
      for row in 0 to 5 loop
        if scene>=12 then
          case row is
            when 0 => coefficient:=0;
            when 1 => coefficient:=1;
            when 2 => coefficient:=8;
            when 3 => coefficient:=16;
            when 4 => coefficient:=17;
            when others => coefficient:=31;
          end case;
          regwrite(16#04000054#,std_logic_vector(to_unsigned(coefficient,32)));
        end if;
        -- Use distinct scanlines: the upstream incomplete-frame map intentionally
        -- retains previously drawn rows until a whole frame has been rendered.
        line<=to_unsigned(scene*6+row,8); lt<='1'; clear_count<='1'; step;
        lt<='0'; clear_count<='0'; step(4); draw<='1'; step; draw<='0'; step(16);
        hb<='1'; step; hb<='0'; timeout:=0;
        while ready/="11" loop
          step; timeout:=timeout+1;
          assert timeout<100000 report "renderer did not finish a scanline" severity failure;
        end loop;
        step(16);
        for i in 0 to 1 loop
          assert count(i)=240 report "incomplete renderer scanline" severity failure;
        end loop;
        for x in 0 to 239 loop
          assert pixels(0)(x)=pixels(1)(x)
            report "renderer mismatch scene=" & integer'image(scene) &
            " row=" & integer'image(row) & " x=" & integer'image(x) &
            " original=" & to_hstring(pixels(0)(x)) & " shared=" & to_hstring(pixels(1)(x)) severity failure;
        end loop;
      end loop;
      report "PASS renderer scene " & integer'image(scene);
    end loop;
    report "PASS shared renderer: 34560 matching pixels across all modes, layers, transforms, OBJ, mosaic, windows, alpha, brighten, darken and saturated coefficients";
    finish;
  end process;
end;
