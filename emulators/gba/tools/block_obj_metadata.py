"""Put sprite priority/coverage metadata in synchronous block RAM.

The original per-line parallel clear prevents memory inference. Its read is
already registered, so keep that latency and clear entries during the idle
period instead. HBlank waits for the clear as well as the color compositor.
"""
import re


def block_obj_metadata(source):
    marker = '      VRAM_Drawer_valid    : in  std_logic\n'
    assert source.count(marker) == 1
    source = source.replace(marker, marker.rstrip() + ";\n      pixel_clear_ready : out std_logic := '0'\n")
    source = source.replace('of tpixel;\n   signal pixelarray : t_pixelarray;',
        '''of std_logic_vector(2 downto 0);
   signal pixelarray : t_pixelarray;
   signal pixel_clear_count : integer range 0 to PIXELCOUNT := 0;
   signal pixel_clear_drain : integer range 0 to 8 := 8;
   signal pixel_clear_done : std_logic := '0';''')
    assert 'signal pixel_clear_done' in source
    source = source.replace("         if (busy = '0') then\n            pixelarray <= (others => ('1', \"11\", '0', '0'));\n         end if;", '''         if busy = '1' then
            pixel_clear_count <= 0;
            pixel_clear_drain <= 8;
            pixel_clear_done <= '0';
         elsif pixel_clear_drain /= 0 then
            -- Flush pending pixel writes before sweeping their metadata.
            pixel_clear_drain <= pixel_clear_drain - 1;
         elsif pixel_clear_count < PIXELCOUNT then
            metadata_addr := pixel_clear_count;
            metadata_be := "11";
            pixel_clear_count <= pixel_clear_count + 1;
            if pixel_clear_count = PIXELCOUNT - 1 then pixel_clear_done <= '1'; end if;
         end if;
         -- synthesis translate_off
         assert drawline = '0' or pixel_clear_done = '1'
            report "Sprite line started before metadata clear" severity failure;
         -- synthesis translate_on''')
    assert "pixelarray <= (others" not in source
    source = source.replace('         Pixel_readback <= pixelarray(target_wait);', '''         Pixel_readback.transparent <= pixelarray(target_wait)(2);
         Pixel_readback.prio <= pixelarray(target_wait)(1 downto 0);
         Pixel_readback.alpha <= '0';
         Pixel_readback.objwnd <= '0';''')
    source = source.replace('pixelarray(target_merge).prio <= Pixel_merge.prio;', '''-- synthesis translate_off
                  assert metadata_be="00" report "Sprite clear overlaps pixel write" severity failure;
                  -- synthesis translate_on
                  metadata_addr := target_merge;
                  metadata_be(0) := '1';
                  metadata_value(1 downto 0) := Pixel_merge.prio;''')
    source = source.replace("pixelarray(target_merge).transparent <= '0';", '''metadata_be(1) := '1';
                     metadata_value(2) := '0';''')
    assert not re.search(r'pixelarray\([^)]*\)\.', source)
    start = source.rindex('   -- Pixel Pipeline')
    prefix, pipeline = source[:start], source[start:]
    pipeline = pipeline.replace('      variable colordata : std_logic_vector(3 downto 0);', '''      variable colordata : std_logic_vector(3 downto 0);
      variable metadata_addr : integer range 0 to PIXELCOUNT-1;
      variable metadata_value : std_logic_vector(2 downto 0);
      variable metadata_be : std_logic_vector(1 downto 0);''')
    pipeline = pipeline.replace('      if rising_edge(clk100) then', '''      if rising_edge(clk100) then
         metadata_addr := 0;
         metadata_value := "111";
         metadata_be := "00";''', 1)
    pos = pipeline.index('      end if;\n   end process;')
    pipeline = pipeline[:pos] + '''         -- synthesis translate_off
         assert metadata_be="00" or enable_wait='0' or metadata_addr/=target_wait
            report "Sprite metadata read/write collision on an active pixel" severity failure;
         -- synthesis translate_on
         if metadata_be(0)='1' then
            pixelarray(metadata_addr)(1 downto 0) <= metadata_value(1 downto 0);
         end if;
         if metadata_be(1)='1' then
            pixelarray(metadata_addr)(2) <= metadata_value(2);
         end if;
''' + pipeline[pos:]
    source = prefix + pipeline
    pos = re.search(r'^begin\s*$', source, re.M).end()
    source = source[:pos] + '\n   pixel_clear_ready <= pixel_clear_done;\n' + source[pos:]
    return source


def wait_obj_metadata(source):
    marker = "   drawer_ready <= '1' when drawstate = IDLE else '0';"
    assert source.count(marker) == 1
    source = source.replace(marker, "   drawer_ready <= '1' when drawstate = IDLE and obj_pixels_cleared = '1' else '0';")
    pos = re.search(r'^begin\s*$', source, re.M).start()
    source = source[:pos] + "   signal obj_pixels_cleared : std_logic;\n" + source[pos:]
    instance = re.search(r'\w+\s*:\s*entity work\.gba_drawer_obj\s+port map\s*\((.*?)\);', source, re.S)
    assert instance
    pos = instance.end() - 2
    source = source[:pos] + ', pixel_clear_ready => obj_pixels_cleared\n   ' + source[pos:]
    return source
