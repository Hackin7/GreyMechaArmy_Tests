// Save/load/rewind are intentionally deferred from the first hardware slice.
// The register primitive remains functional because the core uses its reset
// defaults even when no save-state transaction is ever requested.
module eReg_SavestateV #(
    parameter index = 0,
    parameter Adr   = 0,
    parameter upper = 63,
    parameter lower = 0,
    parameter [63:0] def = 64'd0
) (
    input  wire clk,
    input  wire [63:0] BUS_Din,
    input  wire [9:0] BUS_Adr,
    input  wire BUS_wren,
    input  wire BUS_rst,
    output wire [63:0] BUS_Dout,
    input  wire [upper:lower] Din,
    output reg  [upper:lower] Dout
);
    initial Dout = def[upper:lower];
    always @(posedge clk) begin
        if (BUS_rst)
            Dout <= def[upper:lower];
        else if (BUS_wren && BUS_Adr == Adr + index)
            Dout <= BUS_Din[upper:lower];
    end
    assign BUS_Dout = (BUS_Adr == Adr + index)
                    ? {{(63-upper){1'b0}}, Din, {lower{1'b0}}}
                    : 64'd0;
endmodule

module gb_savestates (
    input wire clk, input wire reset_in, output wire reset_out,
    output wire load_done, input wire increaseSSHeaderCount,
    input wire save, input wire load, input wire [31:0] savestate_address,
    output wire savestate_busy, input wire [7:0] cart_ram_size,
    input wire lcd_vsync, output wire [63:0] BUS_Din,
    output wire [9:0] BUS_Adr, output wire BUS_wren, output wire BUS_rst,
    input wire [63:0] BUS_Dout, output wire loading_savestate,
    output wire saving_savestate, output wire sleep_savestate,
    input wire clock_ena_in, input wire memory_busy,
    output wire [19:0] Save_RAMAddr, output wire [4:0] Save_RAMRdEn,
    output wire [4:0] Save_RAMWrEn, output wire [15:0] Save_RAMWriteData,
    input wire [7:0] Save_RAMReadData_WRAM,
    input wire [7:0] Save_RAMReadData_VRAM,
    input wire [7:0] Save_RAMReadData_ORAM,
    input wire [7:0] Save_RAMReadData_ZRAM,
    input wire [15:0] Save_RAMReadData_CRAM,
    output wire [63:0] bus_out_Din, input wire [63:0] bus_out_Dout,
    output wire [25:0] bus_out_Adr, output wire bus_out_rnw,
    output wire bus_out_ena, output wire [7:0] bus_out_be,
    input wire bus_out_done
);
    assign reset_out = reset_in;
    assign load_done = 1'b0;
    assign savestate_busy = 1'b0;
    assign BUS_Din = 64'd0; assign BUS_Adr = 10'd0;
    assign BUS_wren = 1'b0; assign BUS_rst = reset_in;
    assign loading_savestate = 1'b0; assign saving_savestate = 1'b0;
    assign sleep_savestate = 1'b0;
    assign Save_RAMAddr = 20'd0; assign Save_RAMRdEn = 5'd0;
    assign Save_RAMWrEn = 5'd0; assign Save_RAMWriteData = 16'd0;
    assign bus_out_Din = 64'd0; assign bus_out_Adr = 26'd0;
    assign bus_out_rnw = 1'b0; assign bus_out_ena = 1'b0;
    assign bus_out_be = 8'd0;
endmodule

module gb_statemanager #(
    parameter Softmap_SaveState_ADDR = 0,
    parameter Softmap_Rewind_ADDR = 0
) (
    input wire clk, input wire reset, input wire rewind_on,
    input wire rewind_active, input wire [31:0] savestate_number,
    input wire save, input wire load, output wire sleep_rewind,
    input wire vsync, output wire request_savestate,
    output wire request_loadstate, output wire [31:0] request_address,
    input wire request_busy
);
    assign sleep_rewind = 1'b0;
    assign request_savestate = 1'b0;
    assign request_loadstate = 1'b0;
    assign request_address = 32'd0;
endmodule
