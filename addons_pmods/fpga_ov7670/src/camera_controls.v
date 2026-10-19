// Independent debounce counters; settings are committed between LCD frames.
module camera_controls #(
    parameter integer DEBOUNCE_CYCLES = 1500000
)(
    input wire clk, resetn, frame_boundary,
    input wire [2:0] buttons_n, // [0] grey, [1] left, [2] right
    output reg enabled,
    output reg [6:0] offset
);
    localparam CW = $clog2(DEBOUNCE_CYCLES + 1);
    (* async_reg = "true" *) reg [2:0] sync1, sync2;
    reg [2:0] stable;
    reg [CW-1:0] count [0:2];
    reg [2:0] press;
    reg pending_enabled;
    reg [6:0] pending_offset;
    integer i;
    always @(posedge clk) begin
        if (!resetn) begin
            sync1 <= 3'b111; sync2 <= 3'b111;
            stable <= 3'b111; press <= 0;
            for (i=0; i<3; i=i+1) count[i] <= 0;
            enabled <= 0; offset <= 16;
            pending_enabled <= 0; pending_offset <= 16;
        end else begin
            sync1 <= buttons_n; sync2 <= sync1; press <= 0;
            for (i=0; i<3; i=i+1) begin
                if (sync2[i] == stable[i]) count[i] <= 0;
                else if (count[i] == DEBOUNCE_CYCLES-1) begin
                    stable[i] <= sync2[i]; count[i] <= 0;
                    press[i] <= !sync2[i];
                end else count[i] <= count[i] + 1'b1;
            end
            if (press[0]) pending_enabled <= !pending_enabled;
            // Opposing simultaneous presses cancel.
            if (press[1] && !press[2] && pending_offset >= 4)
                pending_offset <= pending_offset - 7'd4;
            if (press[2] && !press[1] && pending_offset <= 60)
                pending_offset <= pending_offset + 7'd4;
            if (frame_boundary) begin
                enabled <= pending_enabled; offset <= pending_offset;
            end
        end
    end
endmodule
