// Compatibility memories: each read has exactly two rising-edge registers.
module paint_inference #(
    parameter WEIGHTS_FILE = "build/generated/weights.mem"
) (
    input wire clk, resetn,
    // Bundled-data transfer: snapshot stays fixed from request until completion.
    input wire request_toggle,
    input wire [783:0] snapshot,
    output reg done_toggle,
    output reg [3:0] result_digit,
    output reg [31:0] result_cycles
);
    (* async_reg = "true" *) reg [1:0] request_sync;
    reg request_seen;
    reg core_reset;
    reg [1:0] state;
    reg [2:0] warmup;
    reg [31:0] elapsed;
    wire [3:0] digit;
    wire digit_valid;
    wire [9:0] addr_img;
    wire [15:0] addr_const;
    wire [6:0] addr_inter, addr_out;
    wire out_valid;
    wire signed [63:0] val_out;
    reg image_q, image_r;
    reg signed [15:0] const_q, const_r;
    reg signed [63:0] inter_q, inter_r;
    (* ram_style = "block" *) reg signed [15:0] constants [0:50889];
    (* ram_style = "distributed" *) reg signed [63:0] intermediate [0:73];
    initial $readmemh(WEIGHTS_FILE, constants);

    always @(posedge clk) begin
        image_q <= (addr_img < 784) ? snapshot[addr_img] : 1'b0;
        image_r <= image_q;
        const_q <= constants[addr_const];
        const_r <= const_q;
        inter_q <= (addr_inter < 74) ? intermediate[addr_inter] : 64'd0;
        inter_r <= inter_q;
        if (out_valid && !core_reset) intermediate[addr_out] <= val_out;
    end

    neural_net core (
        .clk(clk), .rst(core_reset), .digit(digit), .digit_valid(digit_valid),
        .addr_img(addr_img), .val_img(image_r),
        .addr_const(addr_const), .val_const(const_r),
        .addr_inter(addr_inter), .val_inter(inter_r),
        .addr_out(addr_out), .out_valid(out_valid), .val_out(val_out)
    );
    localparam IDLE=2'd0, WARM=2'd1, RUN=2'd2;
    always @(posedge clk) begin
        if (!resetn) begin
            request_sync <= 0; request_seen <= 0;
            done_toggle <= 0; result_digit <= 15; result_cycles <= 0;
            state <= IDLE; core_reset <= 1; warmup <= 0; elapsed <= 0;
        end else begin
            request_sync <= {request_sync[0], request_toggle};
            case (state)
                IDLE: begin
                    core_reset <= 1;
                    if (request_sync[1] != request_seen) begin
                        request_seen <= request_sync[1];
                        warmup <= 4; state <= WARM;
                    end
                end
                WARM: begin
                    if (warmup == 0) begin
                        core_reset <= 0; elapsed <= 0; state <= RUN;
                    end else warmup <= warmup-1'b1;
                end
                RUN: begin
                    if (digit_valid) begin
                        result_digit <= digit; result_cycles <= elapsed;
                        done_toggle <= ~done_toggle;
                        core_reset <= 1; state <= IDLE;
                    end else elapsed <= elapsed+1'b1;
                end
                default: begin state <= IDLE; core_reset <= 1; end
            endcase
        end
    end
endmodule
