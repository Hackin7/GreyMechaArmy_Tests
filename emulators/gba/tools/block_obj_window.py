"""Clear the object-window RAM between lines without changing read latency."""
import re


def block_obj_window(source):
    marker="   signal linebuffer_objwindow       : std_logic_vector(0 to 239) := (others => '0');"
    assert source.count(marker)==1
    source=source.replace(marker,'''   type window_ram_t is array(0 to 239) of std_logic;
   signal linebuffer_objwindow : window_ram_t := (others=>'0');
   signal window_clear_count : integer range 0 to 240 := 0;
   signal window_clear_done : std_logic := '0';''')
    source,count=re.subn(r"(drawer_ready <= '1' when drawstate = IDLE)(.*? else '0';)",
                        r"\1 and window_clear_done='1'\2",source)
    assert count==1
    start=source.index('   -- line buffer readout')
    prefix,process=source[:start],source[start:]
    process=process.replace('   process (clk100)\n   begin', '''   process (clk100)
      variable window_addr : integer range 0 to 239;
      variable window_data, window_we : std_logic;
   begin''',1)
    marker="         if (pixel_objwnd     = '1') then linebuffer_objwindow(pixel_x_obj) <= '1'; end if;"
    assert process.count(marker)==1
    process=process.replace(marker,'''         window_addr:=0; window_data:='0'; window_we:='0';
         if drawstate=IDLE and window_clear_count<240 then
            -- All object-window reads for the previous line have been issued.
            window_addr:=window_clear_count; window_we:='1';
            window_clear_count<=window_clear_count+1;
            if window_clear_count=239 then window_clear_done<='1'; end if;
            -- synthesis translate_off
            assert pixel_objwnd='0' report "Object-window clear overlaps a pixel write" severity failure;
            -- synthesis translate_on
         elsif pixel_objwnd='1' then
            window_addr:=pixel_x_obj; window_data:='1'; window_we:='1';
         end if;''')
    marker="                     linebuffer_objwindow     <= (others => '0');"
    assert process.count(marker)==1
    process=process.replace(marker,'''                     -- synthesis translate_off
                     assert window_clear_done='1' report "Window RAM not cleared before new line" severity failure;
                     -- synthesis translate_on
                     window_clear_count<=0; window_clear_done<='0';''')
    marker='         objwindow_merge     <= linebuffer_objwindow(linebuffer_addr);'
    assert process.count(marker)==1
    process=process.replace(marker,marker+'''
         if window_we='1' then linebuffer_objwindow(window_addr)<=window_data; end if;
         -- synthesis translate_off
         assert window_we='0' or merge_enable='0' or window_addr/=linebuffer_addr
            report "Object-window RAM collision during merge" severity failure;
         -- synthesis translate_on''')
    return prefix+process
