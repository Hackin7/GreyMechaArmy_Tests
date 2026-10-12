// Independent active-low button synchronizers and 5 ms debounce filters.
module paint_buttons #(
    parameter integer STABLE_CYCLES = 375000,
    parameter integer WIDTH = 6,
    parameter [WIDTH-1:0] INITIAL_PRESSED = 0
) (
    input wire clk, resetn,
    input wire [WIDTH-1:0] buttons_n,
    output reg [WIDTH-1:0] pressed
);
    localparam integer CW = $clog2(STABLE_CYCLES + 1);
    (* async_reg = "true" *) reg [WIDTH-1:0] sync1, sync2;
    reg [CW-1:0] count [0:WIDTH-1];
    integer i;
    always @(posedge clk) begin
        if (!resetn) begin
            sync1 <= {WIDTH{1'b1}};
            sync2 <= {WIDTH{1'b1}};
            pressed <= INITIAL_PRESSED;
            for (i=0; i<WIDTH; i=i+1) count[i] <= 0;
        end else begin
            sync1 <= buttons_n;
            sync2 <= sync1;
            for (i=0; i<WIDTH; i=i+1) begin
                if ((~sync2[i]) == pressed[i]) count[i] <= 0;
                else if (count[i] == STABLE_CYCLES-1) begin
                    pressed[i] <= ~sync2[i];
                    count[i] <= 0;
                end else count[i] <= count[i] + 1'b1;
            end
        end
    end
endmodule

module paint_cursor #(
    parameter integer HOLD_CYCLES = 18750000,
    parameter integer REPEAT_CYCLES = 3000000
) (
    input wire clk, resetn, pause,
    // left, up, down, right
    input wire [3:0] directions,
    output reg [6:0] x,
    output reg [5:0] y
);
    reg [3:0] previous;
    reg [31:0] countdown;
    wire [3:0] effective = {directions[3] & ~directions[0],
                           directions[2] & ~directions[1],
                           directions[1] & ~directions[2],
                           directions[0] & ~directions[3]};
    wire step = effective != 0 && (effective != previous || countdown == 0);
    always @(posedge clk) begin
        if (!resetn) begin
            x <= 28; y <= 28; previous <= 0; countdown <= 0;
        end else if (!pause) begin
            previous <= effective;
            if (effective == 0) countdown <= 0;
            else if (effective != previous) countdown <= HOLD_CYCLES-1;
            else if (countdown == 0) countdown <= REPEAT_CYCLES-1;
            else countdown <= countdown - 1'b1;
            if (step) begin
                if (effective[0] && x != 0) x <= x-1'b1;
                if (effective[3] && x != 95) x <= x+1'b1;
                if (effective[1] && y != 0) y <= y-1'b1;
                if (effective[2] && y != 63) y <= y+1'b1;
            end
        end
    end
endmodule
