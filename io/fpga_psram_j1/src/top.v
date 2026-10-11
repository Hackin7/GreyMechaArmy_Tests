`timescale 1ns/1ps
module top #(parameter ENABLE_QPI=0, parameter OSC_DIV=6,
             parameter QPI_HALF_PERIOD=2, parameter BURST_BYTES=32, parameter TRACE=0,
             parameter SPI_BURST=0, parameter SPI_FAST_READ=0)(
    input wire btn_rst_n, input wire btn_test_n,
    output wire [7:0] led,
    input wire host_sck, input wire host_mosi, input wire host_cs_n,
    output wire host_miso,
    output wire clock_ref,
    inout wire [7:0] pmod_j1
);
    wire clk;
    OSCG #(.DIV(OSC_DIV)) oscillator(.OSC(clk));
    reg [15:0] reference_divider=0;
    always @(posedge clk) reference_divider <= reference_divider+1'b1;
    assign clock_ref = reference_divider[15]; // GP12: system clock / 65536.
    (* async_reg = "true" *) reg [1:0] reset_sync = 0;
    reg [7:0] startup = 0;
    wire reset = !(&startup);
    always @(posedge clk) begin
        reset_sync <= {reset_sync[0],btn_rst_n};
        if (!reset_sync[1]) startup <= 0;
        else if (!(&startup)) startup <= startup + 1'b1;
    end
    (* async_reg = "true" *) reg [1:0] button_sync = 2'b11;
    reg [17:0] debounce = 0;
    reg button_held = 0;
    reg test_pulse = 0;
    always @(posedge clk) begin
        button_sync <= {button_sync[0],btn_test_n};
        test_pulse <= 0;
        if (reset || button_sync[1]) begin debounce <= 0; button_held <= 0; end
        else if (!button_held) begin
            if (&debounce) begin button_held <= 1; test_pulse <= 1; end
            else debounce <= debounce + 1'b1;
        end
    end
    wire ram_cs_n, ram_sck;
    wire [3:0] ram_in, ram_out, ram_oe;
    // Corrected user wiring (J1 rows swapped):
    // CE#=A10, SCLK=A3, IO0=A9, IO1=B10, IO2=B9, IO3=A8.
    // pmod_j1 indices retain the repo's physical pin mapping in pinout.lpf.
    assign pmod_j1[0] = ram_cs_n;
    assign pmod_j1[3] = ram_sck;
    assign pmod_j1[1] = ram_oe[0] ? ram_out[0] : 1'bz;
    assign pmod_j1[4] = ram_oe[1] ? ram_out[1] : 1'bz;
    assign pmod_j1[5] = ram_oe[2] ? ram_out[2] : 1'bz;
    assign pmod_j1[2] = ram_oe[3] ? ram_out[3] : 1'bz;
    assign pmod_j1[7:6] = 2'bzz;
    assign ram_in = {pmod_j1[2],pmod_j1[5],pmod_j1[4],pmod_j1[1]};
    // GP8/9/10/11 on RP2350: SCK/MOSI/MISO/CE#.
    // Dedicated point-to-point return wire; the RP2350 keeps GP10 as input.
    // Real input ports avoid constant-Z assignments erasing sensed inputs
    // during Yosys tristate lowering.
    psram_demo #(.ENABLE_QPI(ENABLE_QPI),.QPI_HALF_PERIOD(QPI_HALF_PERIOD),
        .BURST_BYTES(BURST_BYTES),.SYS_KHZ(310000/OSC_DIV),
        .POWERUP_CYCLES(120000/OSC_DIV),.INIT_HALF_PERIOD(OSC_DIV < 4 ? 3 : 2),.TRACE(TRACE),
        .SPI_BURST(SPI_BURST),.SPI_FAST_READ(SPI_FAST_READ)) demo(
        .clk(clk),.reset(reset),.test_button(test_pulse),
        .host_sck(host_sck),.host_mosi(host_mosi),
        .host_cs_n(host_cs_n),.host_miso(host_miso),
        .ram_cs_n(ram_cs_n),.ram_sck(ram_sck),.ram_dq_in(ram_in),
        .ram_cs_sense(pmod_j1[0]),.ram_sck_sense(pmod_j1[3]),
        .ram_dq_out(ram_out),.ram_dq_oe(ram_oe),.status_led(led));
endmodule
