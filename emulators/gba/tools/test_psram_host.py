"""Run real SPI framing with the PSRAM packet/readback-buffer variant."""
import subprocess
import argparse
from pathlib import Path
from external_host_buffers import relocate_host
w=Path('build/psram-host');w.mkdir(parents=True,exist_ok=True)
p=argparse.ArgumentParser();p.add_argument('--stable-clients',action='store_true');args=p.parse_args()
(w/'host.v').write_text(relocate_host(Path('rtl/gba_host.v').read_text()))
source=Path('sim/tb_gba_host.sv').read_text()
if args.stable_clients:source=source.replace('.POWERUP_CYCLES(20)', '.POWERUP_CYCLES(20),.STABLE_CLIENTS(1)')
marker='if(reply[11]!==3)$fatal(1,"CRC rejection");'
assert marker in source
source=source.replace(marker,marker+'''
        for(i=0;i<64;i=i+1)if(model.memory[32'h7fffc0+i] !== (i^8'h5a))
            $fatal(1,"Bad CRC modified the destination");''')
for half in (100,500):
 fixture=w/f'tb{half}.sv';fixture.write_text(source.replace('#100;',f'#{half};'))
 exe=w/f'host{half}.vvp'
 subprocess.run(['iverilog','-g2012','-s','tb_gba_host','-o',str(exe),str(fixture),str(w/'host.v'),'rtl/gba_psram.v','../gameboy_gbc/rtl/gb_spi_phy.v','../../io/fpga_psram_j1/src/psram_spi.v','../../io/fpga_psram_j1/src/spi_transaction.v','../../io/fpga_psram_j1/src/spi_burst.v','../../io/fpga_psram_j1/sim/aps6404_model.v'],check=True)
 subprocess.run(['vvp',str(exe)],check=True)
