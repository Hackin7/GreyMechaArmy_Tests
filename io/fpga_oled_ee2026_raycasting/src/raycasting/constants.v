`timescale 1ns / 1ps
// constants.v — RGB565 colour palette mirrored from the EE2026 finance-bros
// reference at:
//   WORK/NUS/EE2026/EE2026-Finance-Bros/e_mods/e_mods.srcs/sources_1/new/
//   helpers/constants.v
// Kept in the source tree for reference; raycasting.v duplicates the values
// it needs as localparams because yosys does not resolve hierarchical
// parameter references like `constant.CYAN` (silently ties them to 0).

module constants();
    parameter HEIGHT = 64;
    parameter WIDTH = 96;

    // Color variables
    parameter RED          = 16'b11111_000000_00000;
    parameter GREEN        = 16'b00000_101010_00000;
    parameter BLUE         = 16'b00000_000000_11111;
    parameter YELLOW       = 16'b11111_111111_00000;
    parameter CYAN         = 16'b00000_111111_11111;
    parameter MAGENTA      = 16'b11111_000000_11111;
    parameter ORANGE       = 16'b11111_011000_00000;
    parameter PURPLE       = 16'b01111_000000_11111;
    parameter PINK         = 16'b11111_010010_10111;
    parameter BROWN        = 16'b01111_010100_00000;
    parameter WHITE        = 16'b11111_111111_11111;
    parameter GRAY         = 16'b01010_010101_01010;
    parameter LIGHT_BLUE   = 16'b01111_011111_11111;
    parameter LIGHT_GREEN  = 16'b01000_111111_01000;
    parameter LIGHT_YELLOW = 16'b11111_111111_01000;
    parameter LIGHT_PURPLE = 16'b10111_010000_10111;
    parameter LIGHT_GRAY   = 16'b10101_101010_10101;
    parameter DARK_GRAY    = 16'b00101_001010_00101;
    parameter BLACK        = 16'd0;
endmodule
