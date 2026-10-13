"""Replace graphics RAM banks with clock-stopped PSRAM ports.

Each client owns a disjoint 4 KiB address region. Only three cached words
remain per client; byte enables preserve CPU palette/OAM write semantics.
"""
import re
from prepare_rtl import closing

COUNT = 9

def relocate(source):
    def instance(name, index, aa, ab, din, qa, qb, we, be, read_a=True, width=32, address_max=255):
        pad = '' if width == 32 else f'({31-width} downto 0 => \'0\') & '
        data = din if width == 32 else pad + din
        base = index * 32
        extras = f'''clk_memory=>clk_memory, memory_tick=>memory_tick,
          reset=>external_reset, ready=>scratch_ready({index}),
          mem_req=>scratch_req({index}), mem_read=>scratch_read({index}),
          mem_addr=>scratch_addr({index*13+12} downto {index*13}),
          mem_wdata=>scratch_wdata({base+31} downto {base}),
          mem_be=>scratch_be({index*4+3} downto {index*4}),
          mem_rdata=>scratch_rdata, mem_done=>scratch_done({index})'''
        return f'''{name}: block
          signal din,qa,qb:std_logic_vector(31 downto 0);
        begin
          din <= {data};
          {'' if qa == 'open' else qa + ' <= qa(' + str(width-1) + ' downto 0);'}
          {qb} <= qb({width-1} downto 0);
          storage: entity work.gba_vram_hi_external generic map(READ_A=>{str(read_a).lower()},ADDRESS_MAX=>{address_max},DATA_BITS=>{width})
          port map(clk=>clk100,addr_a=>{aa},addr_b=>{ab},
            datain_a0=>din(7 downto 0),datain_a1=>din(15 downto 8),
            datain_a2=>din(23 downto 16),datain_a3=>din(31 downto 24),
            dataout_a=>qa,dataout_b=>qb,we_a=>{we},be_a=>{be},{extras});
        end block;'''
    for idx,(label,prefix,reader) in enumerate([
        ('goamram','OAMRAM_PROC','OAMRAM_Drawer'),
        ('gpaletteram_bg','PALETTE_BG','PALETTE_BG_Drawer'),
        ('gpaletteram_oam','PALETTE_OAM','PALETTE_OAM_Drawer')]):
        start=source.index(label+' :'); end=source.index('end generate;',start)+len('end generate;')
        we=f"'0' when {prefix}_we=\"0000\" else '1'"
        # A named signal is used for portable VHDL-2008 synthesis.
        text=instance(label,idx,prefix+'_addr',reader+'_addr',prefix+'_datain',prefix+'_dataout',reader+'_data','writing',prefix+'_we',address_max=255 if idx==0 else 127)
        text=text.replace('signal din,qa,qb:', 'signal writing:std_logic;\n          signal din,qa,qb:')
        text=text.replace('din <=',f'writing <= {we};\n          din <=',1)
        source=source[:start]+text+source[end:]
    names=['bg0','bg1','bg2','bg3','obj_color','obj_settings']
    for idx,name in enumerate(names,3):
        label='ilinebuffer_'+name
        start=source.index(label+':'); pm=re.search(r'port\s+map\s*\(',source[start:],re.I)
        pos=start+pm.end()-1; end=closing(source,pos)+2
        ports=dict(re.findall(r'(\w+)\s*=>\s*([^,\n]+)',source[pos+1:end-2]))
        width=3 if name=='obj_settings' else 16
        text=instance(label,idx,ports['addr_a'],ports['addr_b'],ports['datain_a'],'open',ports['dataout_b'],ports['we_a'],'"0001"' if width==3 else '"0011"',False,width)
        source=source[:start]+text+source[end:]
    return source
