// System PLL: OSCG -> higher core clock. Regenerate if input frequency differs:
//   ecppll -i <OSCG_MHz> -o 100 -n ecp5_sys_pll --clkin_name clki --clkout0_name clko -f src/ecp5_sys_pll.v
// Default assumes ~65 MHz at OSCG output (see comments in top.v).
// diamond 3.7 accepts this PLL
// diamond 3.8-3.9 is untested
// diamond 3.10 or higher is likely to abort with error about unable to use feedback signal
// cause of this could be from wrong CPHASE/FPHASE parameters
module ecp5_sys_pll (
	input  clki,
	output clko,
	output locked
);
(*FREQUENCY_PIN_CLKI="65"*) (*FREQUENCY_PIN_CLKOP="100"*) (*ICP_CURRENT="12"*) (*LPF_RESISTOR="8"*) (*MFG_ENABLE_FILTEROPAMP="1"*) (*MFG_GMCREF_SEL="2"*)
	EHXPLLL #(
		.PLLRST_ENA("DISABLED"),
		.INTFB_WAKE("DISABLED"),
		.STDBY_ENABLE("DISABLED"),
		.DPHASE_SOURCE("DISABLED"),
		.OUTDIVIDER_MUXA("DIVA"),
		.OUTDIVIDER_MUXB("DIVB"),
		.OUTDIVIDER_MUXC("DIVC"),
		.OUTDIVIDER_MUXD("DIVD"),
		.CLKI_DIV(13),
		.CLKOP_ENABLE("ENABLED"),
		.CLKOP_DIV(6),
		.CLKOP_CPHASE(2),
		.CLKOP_FPHASE(0),
		.FEEDBK_PATH("CLKOP"),
		.CLKFB_DIV(20)
	) pll_i (
		.RST(1'b0),
		.STDBY(1'b0),
		.CLKI(clki),
		.CLKOP(clko),
		.CLKFB(clko),
		.CLKINTFB(),
		.PHASESEL0(1'b0),
		.PHASESEL1(1'b0),
		.PHASEDIR(1'b1),
		.PHASESTEP(1'b1),
		.PHASELOADREG(1'b1),
		.PLLWAKESYNC(1'b0),
		.ENCLKOP(1'b0),
		.LOCK(locked)
	);
endmodule
