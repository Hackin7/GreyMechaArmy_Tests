// ecp5_dual_pll.v — single EHXPLLL with two outputs:
//   CLKOP = 75   MHz (drives the OLED streaming domain)
//   CLKOS = 12.5 MHz (drives the EE2026 logic domain — fits its
//                     combinational depth with margin)
// VCO = 50 MHz / 2 * 3 * 8 = 600 MHz; CLKOP = 600/8 = 75, CLKOS = 600/48 = 12.5.
module ecp5_dual_pll (
    input  clki,        // 50 MHz from OSCG /6
    output clko_fast,   // 75 MHz
    output clko_slow,   // 12.5 MHz
    output locked
);
(* FREQUENCY_PIN_CLKI="50" *)
(* FREQUENCY_PIN_CLKOP="75" *)
(* FREQUENCY_PIN_CLKOS="12.5" *)
(* ICP_CURRENT="12" *) (* LPF_RESISTOR="8" *) (* MFG_ENABLE_FILTEROPAMP="1" *) (* MFG_GMCREF_SEL="2" *)
EHXPLLL #(
        .PLLRST_ENA("DISABLED"),
        .INTFB_WAKE("DISABLED"),
        .STDBY_ENABLE("DISABLED"),
        .DPHASE_SOURCE("DISABLED"),
        .OUTDIVIDER_MUXA("DIVA"),
        .OUTDIVIDER_MUXB("DIVB"),
        .OUTDIVIDER_MUXC("DIVC"),
        .OUTDIVIDER_MUXD("DIVD"),
        .CLKI_DIV(2),
        .CLKOP_ENABLE("ENABLED"),
        .CLKOP_DIV(8),
        .CLKOP_CPHASE(4),
        .CLKOP_FPHASE(0),
        .CLKOS_ENABLE("ENABLED"),
        .CLKOS_DIV(48),
        .CLKOS_CPHASE(24),
        .CLKOS_FPHASE(0),
        .FEEDBK_PATH("CLKOP"),
        .CLKFB_DIV(3)
    ) pll_i (
        .RST(1'b0),
        .STDBY(1'b0),
        .CLKI(clki),
        .CLKOP(clko_fast),
        .CLKOS(clko_slow),
        .CLKFB(clko_fast),
        .CLKINTFB(),
        .PHASESEL0(1'b0),
        .PHASESEL1(1'b0),
        .PHASEDIR(1'b1),
        .PHASESTEP(1'b1),
        .PHASELOADREG(1'b1),
        .PLLWAKESYNC(1'b0),
        .ENCLKOP(1'b0),
        .ENCLKOS(1'b0),
        .LOCK(locked)
    );
endmodule
