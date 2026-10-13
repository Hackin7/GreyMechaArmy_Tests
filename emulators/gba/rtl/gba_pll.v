module gba_pll #(parameter CORE_DIV=20, FLASH_DIV=8)(input wire osc,input wire reset,
    output wire core_clk,panel_clk,flash_clk,locked);
    // Nominal input 50 MHz, VCO 400 MHz: core 20, panel 80, flash 50 MHz.
    // OSCG DIV=6 is approximately 51.67 MHz; the LPF includes that margin.
    EHXPLLL #(.PLLRST_ENA("ENABLED"),.INTFB_WAKE("DISABLED"),
        .STDBY_ENABLE("DISABLED"),.DPHASE_SOURCE("DISABLED"),
        .CLKI_DIV(5),.CLKFB_DIV(2),.CLKOP_DIV(CORE_DIV),.CLKOP_CPHASE(CORE_DIV/2),.CLKOP_FPHASE(0),
        .CLKOS_DIV(CORE_DIV/4),.CLKOS_CPHASE(CORE_DIV/8),.CLKOS_FPHASE(0),
        .CLKOS2_DIV(FLASH_DIV),.CLKOS2_CPHASE(FLASH_DIV/2),.CLKOS2_FPHASE(0),
        .FEEDBK_PATH("CLKOP"),.CLKOP_ENABLE("ENABLED"),
        .CLKOS_ENABLE("ENABLED"),.CLKOS2_ENABLE("ENABLED")) pll(
        .CLKI(osc),.CLKFB(core_clk),.RST(reset),.STDBY(1'b0),
        .PHASESEL0(1'b0),.PHASESEL1(1'b0),.PHASEDIR(1'b0),.PHASESTEP(1'b0),
        .PLLWAKESYNC(1'b0),.ENCLKOP(1'b0),.ENCLKOS(1'b0),
        .ENCLKOS2(1'b0),.ENCLKOS3(1'b0),.CLKOP(core_clk),
        .CLKOS(panel_clk),.CLKOS2(flash_clk),.CLKINTFB(),.LOCK(locked));
endmodule
