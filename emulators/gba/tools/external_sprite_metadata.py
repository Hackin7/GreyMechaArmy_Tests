"""Externalize sprite priority and object-window payloads, retaining timing."""
import re
from prepare_rtl import closing

def storage(label,addr,readaddr,data,mask,width,index,maximum):
    ports=f'''clk_memory=>clk_memory,memory_tick=>memory_tick,reset=>memory_reset,
      ready=>meta_ready,mem_req=>meta_req,mem_read=>meta_read,mem_addr=>meta_addr,
      mem_wdata=>meta_wdata,mem_be=>meta_be,mem_rdata=>meta_rdata,mem_done=>meta_done'''
    return f'''  {label}:entity work.gba_vram_hi_external
    generic map(ADDRESS_MAX=>{maximum},BIT_MASK_WRITE=>true,DATA_BITS=>{width})
    port map(clk=>clk100,addr_a=>{addr},addr_b=>{readaddr},
      datain_a0=>"00000"&{data},datain_a1=>x"00",datain_a2=>x"00",datain_a3=>x"00",
      dataout_a=>open,dataout_b=>meta_q,we_a=>meta_we,be_a=>"1111",
      bit_be=>(31 downto 3=>'0')&{mask},{ports});
'''

META_PORTS={
 'clk_memory':'in std_logic','memory_tick':'in std_logic','memory_reset':'in std_logic',
 'meta_ready':'out std_logic','meta_req':'out std_logic','meta_read':'out std_logic',
 'meta_addr':'out std_logic_vector(12 downto 0)',
 'meta_wdata':'out std_logic_vector(31 downto 0)','meta_be':'out std_logic_vector(3 downto 0)',
 'meta_rdata':'in std_logic_vector(31 downto 0)','meta_done':'in std_logic'}

def metadata(s):
    s=s.replace("         if busy = '1' then\n            pixel_clear_count", "         if memory_reset='1'then\n            pixel_clear_count<=0;pixel_clear_drain<=8;pixel_clear_done<='0';\n         elsif busy = '1' then\n            pixel_clear_count")
    start=re.search(r'port\s*\(',s,re.I).end()-1;end=closing(s,start)
    s=s[:end]+';\n'+';\n'.join(f'{n}:{t}'for n,t in META_PORTS.items())+s[end:]
    pos=re.search(r'^begin\s*$',s,re.M).start()
    s=s[:pos]+'''  signal metadata_write_addr:integer range 0 to PIXELCOUNT-1:=0;
  signal metadata_write_value,metadata_write_mask:std_logic_vector(2 downto 0):="000";
  signal meta_q:std_logic_vector(31 downto 0);signal meta_we:std_logic;
'''+s[pos:]
    s=s.replace('         Pixel_readback.transparent <= pixelarray(target_wait)(2);','')
    s=s.replace('         Pixel_readback.prio <= pixelarray(target_wait)(1 downto 0);','')
    old='''         if metadata_be(0)='1' then
            pixelarray(metadata_addr)(1 downto 0) <= metadata_value(1 downto 0);
         end if;
         if metadata_be(1)='1' then
            pixelarray(metadata_addr)(2) <= metadata_value(2);
         end if;'''
    assert old in s
    s=s.replace(old,'''         metadata_write_addr<=metadata_addr;metadata_write_value<=metadata_value;
         metadata_write_mask<=metadata_be(1)&metadata_be(0)&metadata_be(0);''')
    pos=re.search(r'^begin\s*$',s,re.M).end()
    s=s[:pos]+'''\n  Pixel_readback.transparent<=meta_q(2);Pixel_readback.prio<=meta_q(1 downto 0);
  meta_we<='0'when metadata_write_mask="000"else '1';
'''+storage('metadata_store','metadata_write_addr','target_wait','metadata_write_value','metadata_write_mask',3,10,'PIXELCOUNT-1')+s[pos:]
    return s

def window(s):
    s=s.replace('         if drawstate=IDLE and window_clear_count<240 then', "         if external_reset='1'then\n            window_clear_count<=0;window_clear_done<='0';\n         elsif drawstate=IDLE and window_clear_count<240 then")
    pos=re.search(r'^begin\s*$',s,re.M).start()
    s=s[:pos]+'''  signal window_write_addr:integer range 0 to 255:=0;
  signal window_write_value,window_write_mask:std_logic_vector(2 downto 0):="000";
  signal window_q:std_logic_vector(31 downto 0);signal window_we_external:std_logic;
'''+s[pos:]
    s=s.replace('         objwindow_merge     <= linebuffer_objwindow(linebuffer_addr);','')
    s=s.replace("         if window_we='1' then linebuffer_objwindow(window_addr)<=window_data; end if;",'''         window_write_addr<=window_addr;window_write_value<="00"&window_data;
         window_write_mask<="00"&window_we;''')
    text=storage('window_store','window_write_addr','linebuffer_addr','window_write_value','window_write_mask',1,9,'255')
    mapping={'meta_ready':'scratch_ready(9)','meta_req':'scratch_req(9)','meta_read':'scratch_read(9)',
     'meta_addr':'scratch_addr(129 downto 117)','meta_wdata':'scratch_wdata(319 downto 288)',
     'meta_be':'scratch_be(39 downto 36)','meta_rdata':'scratch_rdata','meta_done':'scratch_done(9)',
     'meta_q':'window_q','meta_we':'window_we_external','memory_reset':'external_reset'}
    # Replace complete identifiers, not substrings within mem_wdata etc.
    text=re.sub(r'\b('+ '|'.join(mapping)+r')\b',lambda m:mapping[m[0]],text)
    pos=re.search(r'^begin\s*$',s,re.M).end()
    s=s[:pos]+'''\n  objwindow_merge<=window_q(0);
  window_we_external<='0'when window_write_mask="000"else '1';
'''+text+s[pos:]
    # Pass only the sprite metadata client into the object renderer.
    start=re.search(r'entity work.gba_drawer_obj\s+port map\s*\(',s,re.S).end()-1
    end=closing(s,start)
    mapping={'clk_memory':'clk_memory','memory_tick':'memory_tick','memory_reset':'external_reset',
     'meta_ready':'scratch_ready(10)','meta_req':'scratch_req(10)','meta_read':'scratch_read(10)',
     'meta_addr':'scratch_addr(142 downto 130)','meta_wdata':'scratch_wdata(351 downto 320)',
     'meta_be':'scratch_be(43 downto 40)','meta_rdata':'scratch_rdata','meta_done':'scratch_done(10)'}
    return s[:end]+',\n'+','.join(f'{n}=>{v}'for n,v in mapping.items())+s[end:]
