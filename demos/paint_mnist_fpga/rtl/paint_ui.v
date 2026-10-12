module paint_ui #(
    parameter integer INTERVAL_CYCLES = 7500000,
    parameter integer HOLD_CYCLES = 18750000,
    parameter integer REPEAT_CYCLES = 3000000
) (
    input wire clk, resetn,
    input wire [5:0] pressed,
    input wire [9:0] render_address,
    output wire [2:0] render_colour,
    output wire [6:0] cursor_x,
    output wire [5:0] cursor_y,
    output reg [2:0] chosen_colour,
    output reg [783:0] snapshot,
    output reg request_toggle,
    input wire done_toggle,
    input wire [3:0] result_digit,
    output reg [3:0] prediction,
    output reg prediction_valid,
    output wire updating,
    output wire busy
);
    (* ram_style = "distributed" *) reg [2:0] canvas [0:783];
    reg copying, clearing, in_flight, dirty;
    reg [9:0] copy_index, clear_index;
    reg snapshot_has_ink;
    reg [31:0] cooldown, clear_generation, captured_generation;
    reg previous_a, previous_b, armed, pending_click;
    reg stamp_valid, command_valid;
    reg [9:0] last_stamp, command_address;
    reg [2:0] last_colour, command_colour;
    (* async_reg = "true" *) reg [1:0] done_sync;
    reg done_seen;
    integer i;
    initial begin
        for (i=0; i<784; i=i+1) canvas[i] = 0;
    end
    wire a = pressed[4], b = pressed[5];
    wire clear_edge = b && !previous_b;
    wire click = pending_click || (a && !previous_a);
    wire paused = copying || clearing;
    wire [9:0] paint_address = (cursor_y >> 1)*28 + (cursor_x >> 1);
    assign render_colour = render_address < 784 ? canvas[render_address] : 3'd0;
    assign updating = dirty || copying || in_flight || clearing;
    assign busy = copying || in_flight;
    paint_cursor #(.HOLD_CYCLES(HOLD_CYCLES), .REPEAT_CYCLES(REPEAT_CYCLES)) cursor (
        .clk(clk), .resetn(resetn), .pause(paused || clear_edge),
        .directions(pressed[3:0]), .x(cursor_x), .y(cursor_y)
    );
    always @(posedge clk) begin
        if (!resetn) begin
            copying <= 0; clearing <= 1; in_flight <= 0; dirty <= 0;
            copy_index <= 0; clear_index <= 0; snapshot_has_ink <= 0;
            snapshot <= 0; request_toggle <= 0;
            cooldown <= 0; clear_generation <= 0; captured_generation <= 0;
            previous_a <= 0; previous_b <= 0; armed <= 0; pending_click <= 0;
            stamp_valid <= 0; command_valid <= 0;
            last_stamp <= 0; command_address <= 0; last_colour <= 0; command_colour <= 0;
            chosen_colour <= 3; prediction <= 15; prediction_valid <= 0;
            done_sync <= 0; done_seen <= 0;
        end else begin
            previous_a <= a; previous_b <= b;
            done_sync <= {done_sync[0], done_toggle};
            if (cooldown != 0) cooldown <= cooldown-1'b1;
            if (!a) begin armed <= 1; stamp_valid <= 0; end
            if (a && !previous_a && armed) pending_click <= 1;

            if (done_sync[1] != done_seen) begin
                done_seen <= done_sync[1]; in_flight <= 0;
                if (captured_generation == clear_generation && !clear_edge && !clearing) begin
                    prediction <= result_digit; prediction_valid <= 1;
                end
            end

            if (clear_edge) begin
                clearing <= 1; clear_index <= 0; copying <= 0;
                clear_generation <= clear_generation+1'b1;
                prediction_valid <= 0; dirty <= 0;
                armed <= 0; pending_click <= 0;
                stamp_valid <= 0; command_valid <= 0;
            end else if (clearing) begin
                canvas[clear_index] <= 0;
                if (clear_index == 783) clearing <= 0;
                else clear_index <= clear_index+1'b1;
            end else if (copying) begin
                snapshot[copy_index] <= canvas[copy_index] != 0;
                snapshot_has_ink <= snapshot_has_ink || canvas[copy_index] != 0;
                if (copy_index == 783) begin
                    copying <= 0;
                    if (snapshot_has_ink || canvas[copy_index] != 0) begin
                        request_toggle <= ~request_toggle; in_flight <= 1;
                    end else prediction_valid <= 0;
                end else copy_index <= copy_index+1'b1;
            end else if (dirty && !in_flight && cooldown == 0 && !command_valid) begin
                copying <= 1; copy_index <= 0; snapshot_has_ink <= 0;
                captured_generation <= clear_generation;
                dirty <= 0; cooldown <= INTERVAL_CYCLES-1;
            end else begin
                pending_click <= 0;
                if (click && armed) begin
                    if (cursor_x > 66 && cursor_x < 78 && cursor_y > 5 && cursor_y < 29)
                        chosen_colour <= 3;
                    else if (cursor_x > 80 && cursor_x < 92 && cursor_y > 5 && cursor_y < 29)
                        chosen_colour <= 1;
                    else if (cursor_x > 66 && cursor_x < 78 && cursor_y > 34 && cursor_y < 58)
                        chosen_colour <= 2;
                    else if (cursor_x > 80 && cursor_x < 92 && cursor_y > 34 && cursor_y < 58)
                        chosen_colour <= 4;
                end
                // Register a stamp before the RAM write. Remember the last stamp
                // instead of putting a RAM read/compare in its write-enable path.
                if (command_valid) begin
                    canvas[command_address] <= command_colour;
                    command_valid <= 0; dirty <= 1;
                end else if (a && armed && cursor_x < 56 && cursor_y < 56 &&
                    (!stamp_valid || last_stamp != {cursor_y[5:1],cursor_x[5:1]} || last_colour != chosen_colour)) begin
                    command_address <= paint_address; command_colour <= chosen_colour;
                    command_valid <= 1; stamp_valid <= 1;
                    last_stamp <= {cursor_y[5:1],cursor_x[5:1]}; last_colour <= chosen_colour;
                end
            end
        end
    end
endmodule
