module ecp5_gb_pll (
    input  wire clk_50mhz,
    input  wire reset,
    output wire clk_75mhz,
    output wire clk_core,
    output wire clk_flash,
    output wire locked
);
    // This is the same, board-proven PLL arrangement used by arduboy_fx.
    // The Army's ECP5 internal oscillator is reliable; clk_ext is not used
    // as a clock source on this target.
    EHXPLLL #(
        .PLLRST_ENA("ENABLED"),
        .INTFB_WAKE("DISABLED"),
        .STDBY_ENABLE("DISABLED"),
        .DPHASE_SOURCE("DISABLED"),
        .CLKI_DIV(2),
        .CLKFB_DIV(3),
        .CLKOP_DIV(8),
        .CLKOP_CPHASE(4),
        .CLKOP_FPHASE(0),
        .CLKOS_DIV(40),
        .CLKOS_CPHASE(20),
        .CLKOS_FPHASE(0),
        // Existing panel:core ratio is 40:8 = 5:1. A separate output
        // gives flash:core = 40:10 = 4:1 without changing panel timing.
        .CLKOS2_DIV(10),
        .CLKOS2_CPHASE(5),
        .CLKOS2_FPHASE(0),
        .FEEDBK_PATH("CLKOP"),
        .CLKOP_ENABLE("ENABLED"),
        .CLKOS_ENABLE("ENABLED"),
        .CLKOS2_ENABLE("ENABLED")
    ) pll_i (
        .CLKI(clk_50mhz),
        .CLKFB(clk_75mhz),
        .RST(reset),
        .STDBY(1'b0),
        .PHASESEL0(1'b0), .PHASESEL1(1'b0), .PHASEDIR(1'b0),
        .PHASESTEP(1'b0), .PLLWAKESYNC(1'b0), .ENCLKOP(1'b0),
        .ENCLKOS(1'b0), .ENCLKOS2(1'b0), .ENCLKOS3(1'b0),
        .CLKOP(clk_75mhz),
        .CLKOS(clk_core),
        .CLKOS2(clk_flash),
        .CLKINTFB(),
        .LOCK(locked)
    );
endmodule
