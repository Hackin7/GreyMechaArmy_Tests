import { writable } from 'svelte/store';
import { defaultPinout } from './defaultPinout.js';

export const files = writable({
  'top.v': `module top(
	input clk_ext,
	input [4:0] btn,
	output [7:0] led,
	inout [7:0] interconnect,
	inout [7:0] pmod_j1,
	inout [7:0] pmod_j2,
	output oled_scl,
	output oled_sda,
	output oled_dc,
	output oled_cs,
	output oled_rst,
	inout [4:0] s
);
	/*
	 * System clock f_sys (OSCG): Lattice TN-02200 + DS give oscillator + DIV;
	 * exact MHz is PVT-dependent. Practical ways to get a number:
	 * - Run nextpnr: it reports "Max frequency" / slack for the global clock net.
	 * - Scope SPI SCLK during a transfer: f_SCLK = f_sys / (2 * (clk_div + 1))
	 *   with clk_div from firmware spi_init() (see simple_spi_master.v).
	 * Rough same-board estimate: OSCG DIV="3" achieved ~103 MHz in another
	 * build; with DIV="5" here, scale ~103 * 3/5 ~ 62 MHz if comparable.
	 */
	wire clk_int;
	defparam OSCI1.DIV = "5";
	OSCG OSCI1 (.OSC(clk_int));

    /*ifdef USE_SYS_PLL
      wire clk_pll;
      wire pll_locked;
      ecp5_sys_pll pll_sys (
        .clki   (clk_int),
        .clko   (clk_pll),
        .locked (pll_locked)
      );
      wire clk = clk_pll;
      wire unused_pll_locked = pll_locked;
    else*/
      wire clk = clk_int;
    //endif
    
    reg [31:0] counter;
    always @(posedge clk) begin
        counter <= counter + 1;
    end
    assign led = counter[31-:8];
endmodule
`,
  'pinout.lpf': defaultPinout
});

export const activeFile = writable('top.v');
export const terminalLogs = writable('');
