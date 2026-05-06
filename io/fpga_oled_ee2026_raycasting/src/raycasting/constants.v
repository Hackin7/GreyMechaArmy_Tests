// constants.v — minimal RGB565 constants module the raycasting source
// depends on (referenced as `constants constant(); constant.CYAN, etc.`).
// In the original lab this came from a shared utility file we don't have.
module constants;
    parameter [15:0] BLACK   = 16'h0000;
    parameter [15:0] WHITE   = 16'hFFFF;
    parameter [15:0] RED     = 16'hF800;
    parameter [15:0] GREEN   = 16'h07E0;
    parameter [15:0] BLUE    = 16'h001F;
    parameter [15:0] CYAN    = 16'h07FF;
    parameter [15:0] MAGENTA = 16'hF81F;
    parameter [15:0] YELLOW  = 16'hFFE0;
endmodule
