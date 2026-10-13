#!/usr/bin/env python3
"""Generate an isolated full-BIOS/IWRAM/lower-VRAM EBR configuration.

Upper VRAM retains its synchronous interface behind a clock-stop cache.
Graphics scratch memories move to SPI PSRAM; priority banks own all 56 EBRs.
Run on Linux from emulators/gba. Does not replace the working board image.
"""
import argparse
import re
import subprocess
from pathlib import Path
from prepare_rtl import closing, prepare
from compact_verilog import compact
from external_graphics_memories import relocate
from remove_duplicate_rom_cache import replace_cache
from external_host_buffers import relocate_host
from external_sprite_metadata import metadata, window
from share_cpu_shift_read import share_shift_read

PORTS = {
    'clk_memory': 'in std_logic', 'memory_tick': 'in std_logic',
    'upper_ready': 'out std_logic', 'upper_req': 'out std_logic',
    'upper_read': 'out std_logic', 'upper_addr': 'out std_logic_vector(12 downto 0)',
    'upper_wdata': 'out std_logic_vector(31 downto 0)',
    'upper_be': 'out std_logic_vector(3 downto 0)',
    'upper_rdata': 'in std_logic_vector(31 downto 0)', 'upper_done': 'in std_logic',
    'scratch_ready': 'out std_logic_vector(10 downto 0)',
    'scratch_req': 'out std_logic_vector(10 downto 0)',
    'scratch_read': 'out std_logic_vector(10 downto 0)',
    'scratch_addr': 'out std_logic_vector(142 downto 0)',
    'scratch_wdata': 'out std_logic_vector(351 downto 0)',
    'scratch_be': 'out std_logic_vector(43 downto 0)',
    'scratch_rdata': 'in std_logic_vector(31 downto 0)',
    'scratch_done': 'in std_logic_vector(10 downto 0)',
}


def add_ports(source):
    start = re.search(r'entity\s+\w+\s+is.*?port\s*\(', source, re.S | re.I).end()-1
    end = closing(source, start)
    return source[:end] + ';\n' + ';\n'.join(f' {n}: {t}' for n,t in PORTS.items()) + '\n' + source[end:]


def map_child(source, child):
    start = re.search(r'entity\s+work\.'+child+r'\b.*?port\s+map\s*\(', source, re.S|re.I).end()-1
    end = closing(source,start)
    return source[:end] + ',\n' + ',\n'.join(f' {n} => {n}' for n in PORTS) + '\n' + source[end:]


def generate(folder,line_slots=2,shared_shift_read=True):
    vendor=Path('vendor/openfpga-GBA/src/fpga/gba')
    portable=folder/'portable'
    prepare(vendor,portable,True,True,True,True,True,True,True,True)
    if shared_shift_read:
        cpu=portable/'gba_cpu.vhd';cpu.write_text(share_shift_read(cpu.read_text()))
    cache=portable/'cache.vhd';cache.write_text(replace_cache(cache.read_text()))
    obj=portable/'gba_drawer_obj.vhd';obj.write_text(metadata(obj.read_text()))
    for name,child in [('gba_top','gba_gpu'),('gba_gpu','gba_gpu_drawer'),('gba_gpu_drawer',None)]:
        path=portable/(name+'.vhd'); s=add_ports(path.read_text())
        if child:s=map_child(s,child)
        else:
            start=s.index('ivram_hi:')
            pm=re.search(r'port\s+map\s*\(',s[start:],re.I)
            pos=start+pm.end()-1; end=closing(s,pos)+2
            old=s[pos+1:end-2]
            old=re.sub(r'\s*(?:datain_b\d|we_b|be_b)\s*=>[^,\n]+,?', '',old)
            old=old.rstrip().rstrip(',')
            extra='clk_memory=>clk_memory, memory_tick=>memory_tick, reset=>external_reset, ready=>upper_ready, mem_req=>upper_req, mem_read=>upper_read, mem_addr=>upper_addr, mem_wdata=>upper_wdata, mem_be=>upper_be, mem_rdata=>upper_rdata, mem_done=>upper_done'
            s=s[:start]+'ivram_hi: entity work.gba_vram_hi_external port map('+old+', '+extra+');'+s[end:]
            s=relocate(s)
            s=window(s)
        path.write_text(s)
    wrapper=Path('rtl/gba_core_wrapper.sv').read_text().replace('module gba_core_wrapper (','module gba_core_wrapper_priority (')
    wrapper=wrapper.replace(' input wire clk_100,', ''' input wire clk_memory,memory_tick,
 output wire upper_ready,upper_req,upper_read,output wire [12:0] upper_addr,
 output wire [31:0] upper_wdata,output wire [3:0] upper_be,
 input wire [31:0] upper_rdata,input wire upper_done,
 output wire [10:0] scratch_ready,scratch_req,scratch_read,
 output wire [142:0] scratch_addr,output wire [351:0] scratch_wdata,
 output wire [43:0] scratch_be,input wire [31:0] scratch_rdata,
 input wire [10:0] scratch_done,
 input wire clk_100,''')
    wrapper=wrapper.replace('gba_top core (','gba_top core (\n'+','.join(f'.{n}({n})' for n in PORTS)+',')
    (folder/'gba_core_wrapper_priority.sv').write_text(wrapper)
    top=Path('rtl/top.v').read_text()
    gate='''
    wire clk_emulator,upper_ready,upper_req,upper_read,upper_done;
    wire [12:0] upper_addr;wire [31:0] upper_wdata,upper_rdata;wire [3:0] upper_be;
    wire [10:0] scratch_ready,scratch_req,scratch_read,scratch_done;
    wire [142:0] scratch_addr;wire [351:0] scratch_wdata;
    wire [43:0] scratch_be;wire [31:0] scratch_rdata;
    wire pixel_ready,panel_data_ready,lcd_write_req,lcd_read_req,lcd_write_done,lcd_read_done;
    wire [22:0] lcd_write_addr,lcd_read_addr;wire [31:0] lcd_write_data,lcd_read_data;
    wire [3:0] lcd_write_be;
    wire clk_panel_display;reg panel_tick=1;
    always @(negedge clk_panel)panel_tick<=core_reset||panel_data_ready;
    DCCA panel_payload_clock(.CLKI(clk_panel),.CE(panel_tick),.CLKO(clk_panel_display));
    reg memory_tick=1;
    always @(negedge clk_core) memory_tick<=core_reset||(upper_ready&&(&scratch_ready)&&pixel_ready);
    DCCA emulator_clock(.CLKI(clk_core),.CE(memory_tick),.CLKO(clk_emulator));
'''
    top=top.replace('    wire ext_req,',gate+'    wire ext_req,')
    top=top.replace('gba_psram #(.ASYNC_CLOCK(1)) ram(', 'gba_memory_fabric ram(.step(memory_tick),.upper_req(upper_req),.upper_read(upper_read),.upper_addr(upper_addr),.upper_wdata(upper_wdata),.upper_be(upper_be),.upper_rdata(upper_rdata),.upper_done(upper_done),')
    top=top.replace('gba_memory_fabric ram(', 'gba_memory_fabric ram('+','.join(f'.{n}({n})' for n in PORTS if n.startswith('scratch_') and n!='scratch_ready')+',')
    lcd_ports=['lcd_write_req','lcd_read_req','lcd_write_addr','lcd_read_addr','lcd_write_data','lcd_write_be','lcd_write_done','lcd_read_done','lcd_read_data']
    top=top.replace('gba_memory_fabric ram(', 'gba_memory_fabric ram('+','.join(f'.{n}({n})' for n in lcd_ports)+',')
    top=top.replace('.video_addr({7\'h10,vram_addr,2\'b00})','.video_addr(vram_addr)')
    top=top.replace('    wire flash_clk_wire,','''    wire rom_raw_done; wire [31:0] rom_raw_data,rom_raw_second;
    gba_step_response rom_response(.clk(clk_core),.reset(core_reset),.step(memory_tick),
        .done(rom_raw_done),.data(rom_raw_data),.pending(rom_done),.held(rom_data));
    gba_step_response rom_response_second(.clk(clk_core),.reset(core_reset),.step(memory_tick),
        .done(rom_raw_done),.data(rom_raw_second),.pending(),.held(rom_second));
    wire flash_clk_wire,''')
    top=top.replace('.request(rom_read),.address(rom_addr),.done(rom_done),.data(rom_data),.second_data(rom_second)', '.request(rom_read&&memory_tick),.address(rom_addr),.done(rom_raw_done),.data(rom_raw_data),.second_data(rom_raw_second)')
    top=top.replace('gba_core_wrapper gba(.clk_100(clk_core)', 'gba_core_wrapper_priority gba('+','.join(f'.{n}({n})' for n in PORTS if n!='clk_memory')+',.clk_memory(clk_core),.clk_100(clk_emulator)')
    top=top.replace('.core_reset(core_reset),.pixel_we(pixel_we)', '.core_reset(core_reset),.pixel_we(pixel_we&&memory_tick)')
    slots=1 if line_slots==2 else 2
    top=top.replace('gba_lines lines(',f'gba_lines_psram #(.SLOT_BITS({slots})) lines(.memory_tick(memory_tick),.pixel_ready(pixel_ready),.panel_data_ready(panel_data_ready),'+','.join(f'.{n}({v})'for n,v in [('write_req','lcd_write_req'),('write_addr','lcd_write_addr'),('write_data','lcd_write_data'),('write_be','lcd_write_be'),('write_done','lcd_write_done'),('read_req','lcd_read_req'),('read_addr','lcd_read_addr'),('read_done','lcd_read_done'),('read_data','lcd_read_data')])+',')
    top=top.replace('.panel_clk(clk_panel),.panel_reset', '.panel_clk(clk_panel_display),.panel_reset')
    top=top.replace('gba_display display(.clk(clk_panel)', 'gba_display display(.clk(clk_panel_display)')
    top=top.replace('gba_buttons #(.CLK_HZ(21000000))', 'gba_buttons #(.CLK_HZ(21000000),.SHARED_DEBOUNCE(1))')
    (folder/'top.v').write_text(top)
    # Keep all small board buffers out of EBRs, including the panel command ROM.
    for name in ['gba_host.v','gba_lines.v','gba_oled_init.v','gba_gc9a01_init_rom.vh']:
        style='logic' if name=='gba_gc9a01_init_rom.vh' else 'distributed'
        text=Path('rtl',name).read_text().replace('ram_style="block"',f'ram_style="{style}"').replace('ram_style = "block"',f'ram_style = "{style}"')
        if name=='gba_host.v':text=relocate_host(text)
        if name=='gba_lines.v':text=text.replace('reg [15:0] pixels', '(* ram_style="distributed" *) reg [15:0] pixels')
        if name=='gba_host.v':text=text.replace('reg [31:0] read_buffer','(* ram_style="distributed" *) reg [31:0] read_buffer')
        (folder/name).write_text(text)


def core(folder):
    make=Path('Makefile').read_text(); vendor='vendor/openfpga-GBA/src/fpga/gba'
    def files(variable):
        return re.search(r'^'+variable+r' := (.*)$',make,re.M)[1].replace('$(VENDOR)',vendor).split()
    mem=folder/'mem';work=folder/'work';mem.mkdir(exist_ok=True);work.mkdir(exist_ok=True)
    common=['ghdl','-a','--std=08','-fsynopsys','-frelaxed']
    subprocess.run(common+['--work=mem','--workdir='+str(mem)]+files('MEM_VHDL'),check=True)
    sources=[]
    for source in files('GBA_VHDL'):
        if source.endswith('/gba_drawer_obj.vhd'):sources.append('rtl/bram_priority/gba_vram_hi_external.vhd')
        sources.append(str(folder/'portable'/Path(source).name) if source.startswith(vendor) else source)
    subprocess.run(common+['-P'+str(mem),'--workdir='+str(work)]+sources,check=True)
    command=['ghdl','--synth','--std=08','-fsynopsys','-frelaxed','-P'+str(mem),'--workdir='+str(work),'--out=verilog','-gExternalFastMemory=true','-gExternalVRAMLow=true','-gROMCacheSize=64','-gSoftmap_GBA_FLASH_ADDR=131072','-gSoftmap_GBA_EEPROM_ADDR=98304','-gSoftmap_GBA_WRam_ADDR=0','-gSoftmap_GBA_Gamerom_ADDR=0','-gSoftmap_SaveState_ADDR=0',"-gturbosound='0'",'gba_top']
    with (folder/'gba_top.v').open('w') as output:subprocess.run(command,stdout=output,check=True)
    path=folder/'gba_top.v';s=compact(path.read_text(),folder)
    # ROM lookup tables emitted as nNN arrays must remain combinational logic.
    s=re.sub(r'(?m)^(\s*reg (?:\[[^\n]+?\] )?(?!n\d+\b)\w+\[\d+:\d+\][^\n]*)',r'(* ram_style="distributed" *) \1',s)
    path.write_text(s)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--work',type=Path,default=Path('/tmp/greymecha_gba_bram_priority'));parser.add_argument('--core',action='store_true');parser.add_argument('--line-slots',type=int,choices=(2,4),default=2)
    parser.add_argument('--shared-shift-read',action='store_true',default=True)
    parser.add_argument('--no-shared-shift-read',action='store_false',dest='shared_shift_read')
    args=parser.parse_args();args.work.mkdir(parents=True,exist_ok=True);generate(args.work,args.line_slots,args.shared_shift_read)
    if args.core:core(args.work)
