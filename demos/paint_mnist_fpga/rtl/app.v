// Clock-domain boundary: request/done toggles accompany stable snapshot/result buses.
module paint_app #(
    parameter integer DEBOUNCE_CYCLES=375000,
    parameter integer INTERVAL_CYCLES=7500000,
    parameter integer HOLD_CYCLES=18750000,
    parameter integer REPEAT_CYCLES=3000000,
    parameter WEIGHTS_FILE="build/generated/weights.mem"
) (
    input wire ui_clk, nn_clk, resetn_ui, resetn_nn,
    input wire [5:0] buttons_n,
    input wire [15:0] pixel_index,
    output wire [15:0] pixel_data,
    output wire [3:0] prediction,
    output wire prediction_valid, busy, updating
);
    wire [5:0] pressed;
    wire [9:0] canvas_address;
    wire [2:0] canvas_colour, chosen_colour;
    wire [6:0] cursor_x;
    wire [5:0] cursor_y;
    wire [783:0] snapshot;
    wire request_toggle, done_toggle;
    wire [3:0] result_digit;
    wire [31:0] result_cycles;
    // Treat A as held until a release has actually passed the debounce filter.
    // Otherwise its initial unpressed output would arm painting during startup.
    paint_buttons #(.STABLE_CYCLES(DEBOUNCE_CYCLES), .INITIAL_PRESSED(6'b010000)) buttons (
        .clk(ui_clk), .resetn(resetn_ui), .buttons_n(buttons_n), .pressed(pressed)
    );
    paint_ui #(.INTERVAL_CYCLES(INTERVAL_CYCLES), .HOLD_CYCLES(HOLD_CYCLES),
               .REPEAT_CYCLES(REPEAT_CYCLES)) ui (
        .clk(ui_clk), .resetn(resetn_ui), .pressed(pressed),
        .render_address(canvas_address), .render_colour(canvas_colour),
        .cursor_x(cursor_x), .cursor_y(cursor_y), .chosen_colour(chosen_colour),
        .snapshot(snapshot), .request_toggle(request_toggle),
        .done_toggle(done_toggle), .result_digit(result_digit),
        .prediction(prediction), .prediction_valid(prediction_valid),
        .updating(updating), .busy(busy)
    );
    paint_inference #(.WEIGHTS_FILE(WEIGHTS_FILE)) inference (
        .clk(nn_clk), .resetn(resetn_nn), .request_toggle(request_toggle),
        .snapshot(snapshot), .done_toggle(done_toggle), .result_digit(result_digit),
        .result_cycles(result_cycles)
    );
    paint_renderer renderer (
        .clk(ui_clk), .resetn(resetn_ui), .pixel_index(pixel_index),
        .canvas_address(canvas_address), .canvas_colour(canvas_colour),
        .cursor_x(cursor_x), .cursor_y(cursor_y), .chosen_colour(chosen_colour),
        .prediction(prediction), .prediction_valid(prediction_valid),
        .updating(updating), .pixel_data(pixel_data)
    );
endmodule
