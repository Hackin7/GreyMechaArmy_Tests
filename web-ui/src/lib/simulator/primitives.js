// Simulation models only. Never supplied to hardware synthesis.
export const primitiveDeclarations = `
(* blackbox *) module OSCG(output OSC); parameter DIV="6"; endmodule
(* blackbox *) module ODDRX1F(input SCLK,RST,D0,D1,output Q); parameter GSR="ENABLED"; endmodule
(* blackbox *) module EHXPLLL #(
 parameter PLLRST_ENA="DISABLED", INTFB_WAKE="DISABLED", STDBY_ENABLE="DISABLED",
 DPHASE_SOURCE="DISABLED", OUTDIVIDER_MUXA="DIVA", OUTDIVIDER_MUXB="DIVB",
 OUTDIVIDER_MUXC="DIVC", OUTDIVIDER_MUXD="DIVD", CLKI_DIV=2,
 CLKOP_ENABLE="ENABLED", CLKOP_DIV=8, CLKOP_CPHASE=4, CLKOP_FPHASE=0,
 FEEDBK_PATH="CLKOP", CLKFB_DIV=3
)(input RST,STDBY,CLKI,CLKFB,PHASESEL0,PHASESEL1,PHASEDIR,PHASESTEP,
 PHASELOADREG,PLLWAKESYNC,ENCLKOP,output CLKOP,CLKINTFB,LOCK); endmodule
`;

export const primitiveModels = `
module OSCG(output OSC);
 parameter DIV="6";
 assign OSC = greymecha_sim.gm_osc;
endmodule
module ODDRX1F(input SCLK,RST,D0,D1,output Q);
 parameter GSR="ENABLED";
 reg d0_r=0, d1_r=0;
 always @(posedge SCLK or posedge RST)
   if(RST) begin d0_r<=0; d1_r<=0; end
   else begin d0_r<=D0; d1_r<=D1; end
 assign Q = SCLK ? d0_r : d1_r;
endmodule
module EHXPLLL #(
 parameter PLLRST_ENA="DISABLED", INTFB_WAKE="DISABLED", STDBY_ENABLE="DISABLED",
 DPHASE_SOURCE="DISABLED", OUTDIVIDER_MUXA="DIVA", OUTDIVIDER_MUXB="DIVB",
 OUTDIVIDER_MUXC="DIVC", OUTDIVIDER_MUXD="DIVD", CLKI_DIV=2,
 CLKOP_ENABLE="ENABLED", CLKOP_DIV=8, CLKOP_CPHASE=4, CLKOP_FPHASE=0,
 FEEDBK_PATH="CLKOP", CLKFB_DIV=3
)(input RST,STDBY,CLKI,CLKFB,PHASESEL0,PHASESEL1,PHASEDIR,PHASESTEP,
 PHASELOADREG,PLLWAKESYNC,ENCLKOP,output CLKOP,CLKINTFB,LOCK);
 assign CLKOP = greymecha_sim.gm_pll & ~RST & ~STDBY;
 assign CLKINTFB = CLKOP;
 assign LOCK = greymecha_sim.gm_lock & ~RST & ~STDBY;
endmodule
`;

export const pixelPreviewModel = `
module oled_gc9a01 #(
 parameter integer CLK_HZ=75000000,
 parameter [7:0] INIT_SPI_CLK_DIV=8'd4,
 parameter [0:0] SWAP_RB=1'b1
)(input clk,resetn, output reg [15:0] pixel_index=0, input [15:0] pixel_data,
 output oled_scl,oled_sda,oled_dc,oled_cs,oled_rst,
 output reg init_done=0,streaming=0);
 reg [1:0] gm_phase=0;
 reg [31:0] gm_sequence=0;
 reg [15:0] gm_index=0,gm_data=0;
 always @(posedge clk) begin
   if(!resetn) begin
     pixel_index<=0; gm_phase<=0; gm_sequence<=0;
     gm_index<=0; gm_data<=0; init_done<=0; streaming<=0;
   end else begin
     init_done<=1; streaming<=1; gm_phase<=gm_phase+1;
     if(gm_phase==3) begin
       gm_index<=pixel_index; gm_data<=pixel_data; gm_sequence<=gm_sequence+1;
       pixel_index <= pixel_index==57599 ? 16'd0 : pixel_index+16'd1;
     end
   end
 end
 assign oled_scl=0; assign oled_sda=0; assign oled_dc=1; assign oled_cs=1;
 assign oled_rst=resetn;
endmodule
`;
