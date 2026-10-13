import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from bind_board_clocks import bind
from check_board_timing import check_constraints,check_fmax


def design(quad=True):
    cells={'clocks.pll':{'type':'EHXPLLL','connections':{'CLKOP':[10],'CLKOS':[11],'CLKOS2':[12]}},
           'consumer':{'type':'TRELLIS_FF','connections':{'CLK':[10],'D':[20],'Q':[21]}}}
    if quad:cells['quad_clock.clocks.pll']={'type':'EHXPLLL','connections':{'CLKOS2':[13]}}
    aliases={'buttons.clk':10,'cache.clk':10,'lines.panel_clk':11,'ram.phy.clk':12}
    if quad:aliases['flash.phy.clk']=13
    return {'modules':{'top':{'cells':cells,'ports':{'input':{'bits':[20]}},
        'netnames':{name:{'bits':[bit],'hide_name':0,'attributes':{'src':'fixture'}} for name,bit in aliases.items()}}}}


class ClockConstraints(unittest.TestCase):
    frequencies={'clk_core':24,'clk_panel':97,'clk_ram':120,'clk_flash':155}

    def test_renamed_outputs_keep_all_connectivity(self):
        netlist=design();before=copy.deepcopy(netlist)
        bindings=bind(netlist,self.frequencies)
        self.assertEqual(netlist['modules']['top']['cells'],before['modules']['top']['cells'])
        self.assertEqual(netlist['modules']['top']['ports'],before['modules']['top']['ports'])
        self.assertEqual(set(netlist['modules']['top']['netnames']),set(self.frequencies))
        self.assertEqual({b['name']:b['mhz'] for b in bindings},self.frequencies)

    def test_shared_spi_clock_uses_stricter_target(self):
        bindings=bind(design(False),dict(self.frequencies,clk_flash=53))
        clock=next(b for b in bindings if b['name']=='clk_ram')
        self.assertEqual(clock['roles'],['clk_ram','clk_flash'])
        self.assertEqual(clock['mhz'],120)
        self.assertEqual(len(bindings),3)

    def test_missing_pll_or_conflicting_name_fails(self):
        netlist=design();del netlist['modules']['top']['cells']['clocks.pll']
        with self.assertRaises(ValueError):bind(netlist,self.frequencies)
        netlist=design();netlist['modules']['top']['netnames']['clk_core']={'bits':[99]}
        with self.assertRaises(ValueError):bind(netlist,self.frequencies)

    def test_ignored_missing_and_wrong_targets_fail(self):
        bindings=bind(design(),self.frequencies)
        good='\n'.join(f"Info: constraining clock net '{b['name']}' to {b['mhz']:.2f} MHz" for b in bindings)
        check_constraints(good,bindings)
        for bad in (good+'\nWarning: ignoring clock constraint',good.replace('155.00','12.00'),good.split('\n',1)[1]):
            with self.assertRaises(ValueError):check_constraints(bad,bindings)

    def test_fmax_requires_every_target_and_checks_other_domains(self):
        bindings=bind(design(),self.frequencies)
        good={'fmax':{'$glbnet$'+b['name']:{'constraint':b['mhz'],'achieved':b['mhz']+1} for b in bindings}}
        check_fmax(good,bindings)
        for field,value in (('achieved',154),('constraint',12)):
            bad=copy.deepcopy(good);bad['fmax']['$glbnet$clk_flash'][field]=value
            with self.assertRaises(ValueError):check_fmax(bad,bindings)
        bad=copy.deepcopy(good);del bad['fmax']['$glbnet$clk_ram']
        with self.assertRaises(ValueError):check_fmax(bad,bindings)
        bad=copy.deepcopy(good);bad['fmax']['host_sck']={'constraint':12,'achieved':11}
        with self.assertRaises(ValueError):check_fmax(bad,bindings)


if __name__=='__main__':unittest.main()
