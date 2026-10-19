// Post-camera RGB demonstration, not raw sensor black-level calibration.
module rgb_offset(
    input wire [15:0] pixel,
    input wire enabled,
    input wire [6:0] offset,
    output wire [15:0] corrected
);
    wire [7:0] r = {pixel[15:11], pixel[15:13]};
    wire [7:0] g = {pixel[10:5], pixel[10:9]};
    wire [7:0] b = {pixel[4:0], pixel[4:2]};
    wire [7:0] cr = r > offset ? r - {1'b0,offset} : 8'd0;
    wire [7:0] cg = g > offset ? g - {1'b0,offset} : 8'd0;
    wire [7:0] cb = b > offset ? b - {1'b0,offset} : 8'd0;
    assign corrected = enabled ? {cr[7:3], cg[7:2], cb[7:3]} : pixel;
endmodule
