`timescale 1ns/1ps
// Transport and test coordinator, separated from FPGA primitives for simulation.
module psram_demo #(parameter POWERUP_CYCLES=20000)(
    input wire clk, input wire reset, input wire test_button,
    input wire host_sck, input wire host_mosi, input wire host_cs_n,
    output wire host_miso,
    output wire ram_cs_n, output wire ram_sck,
    input wire ram_cs_sense, input wire ram_sck_sense,
    input wire [3:0] ram_dq_in, output wire [3:0] ram_dq_out,
    output wire [3:0] ram_dq_oe, output wire [7:0] status_led
);
    wire command_valid;
    wire [7:0] opcode, command_data;
    wire [23:0] command_address;
    reg request;
    reg [1:0] operation;
    reg [23:0] address;
    reg [7:0] write_data;
    wire ram_busy, ram_ready, ram_done;
    wire [7:0] read_data;
    wire [23:0] device_id;
    localparam IDLE=0, WAIT_OP=1, TEST_WRITE=2, TEST_WRITE_WAIT=3,
               TEST_READ=4, TEST_READ_WAIT=5;
    reg [2:0] state;
    reg [23:0] test_base, result_address;
    reg [7:0] test_index, result_data, expected_data, error_code;
    reg test_pass;
    wire occupied = ram_busy || state != IDLE;
    wire id_good = ram_ready && device_id[15:8] == 8'h5d;
    wire [7:0] status = {3'b0,id_good,(error_code != 0),test_pass,ram_ready,occupied};
    wire [63:0] response = {8'h50,status,result_data,expected_data,result_address,error_code};
    assign status_led = {3'b0,id_good,(error_code != 0),test_pass,ram_ready,occupied};
    wire [23:0] test_address = test_base + {16'b0,test_index};
    wire [7:0] test_pattern = test_address[7:0] ^ test_address[15:8] ^ test_address[23:16] ^ 8'ha5;
    wire [7:0] address_pattern = address[7:0] ^ address[15:8] ^ address[23:16] ^ 8'ha5;
    // Observe actual pad inputs, not only the signals intended for output.
    // Activity bits: CE low/high, SCK low/high, IO0 low/high, IO1 low/high.
    reg [7:0] pin_activity;
    reg [23:0] clock_edges;
    reg previous_sck;
    wire [7:0] pin_levels = {2'b0,ram_cs_sense,ram_sck_sense,ram_dq_in};
    always @(posedge clk) begin
        previous_sck <= ram_sck_sense;
        if (reset) begin
            pin_activity <= 0; clock_edges <= 0; previous_sck <= 0;
        end else begin
            if (ram_cs_sense) pin_activity[1] <= 1;
            else begin
                pin_activity[0] <= 1;
                if (ram_sck_sense) pin_activity[3] <= 1;
                else pin_activity[2] <= 1;
                if (ram_dq_in[0]) pin_activity[5] <= 1;
                else pin_activity[4] <= 1;
                if (!ram_dq_oe[1]) begin
                    if (ram_dq_in[1]) pin_activity[7] <= 1;
                    else pin_activity[6] <= 1;
                end
                if (ram_sck_sense && !previous_sck) clock_edges <= clock_edges + 1'b1;
            end
        end
    end
    host_spi host(.clk(clk),.reset(reset),.sck(host_sck),.mosi(host_mosi),
        .cs_n(host_cs_n),.response(response),.miso(host_miso),
        .command_valid(command_valid),.opcode(opcode),
        .address(command_address),.data(command_data));
    psram_spi #(.POWERUP_CYCLES(POWERUP_CYCLES)) ram(.clk(clk),.reset(reset),
        .request(request),.operation(operation),.address(address),.write_data(write_data),
        .busy(ram_busy),.ready(ram_ready),.done(ram_done),.read_data(read_data),
        .device_id(device_id),.cs_n(ram_cs_n),.sck(ram_sck),
        .dq_in(ram_dq_in),.dq_out(ram_dq_out),.dq_oe(ram_dq_oe));

    always @(posedge clk) begin
        request <= 0;
        if (reset) begin
            state <= IDLE; request <= 0; operation <= 0; address <= 0;
            write_data <= 0; test_base <= 0; test_index <= 0;
            result_address <= 0; result_data <= 0; expected_data <= 0;
            error_code <= 0; test_pass <= 0;
        end else begin
            case (state)
                IDLE: if (!ram_busy && ram_ready && test_button) begin
                    test_base <= 0; test_index <= 0; test_pass <= 0;
                    error_code <= 0; state <= TEST_WRITE;
                end else if (command_valid && opcode != 0) begin
                    if (ram_busy) error_code <= 1;
                    else if (opcode > 6) error_code <= 2;
                    else if (command_address[23] ||
                             (opcode == 4 && command_address > 24'h7fff00))
                        error_code <= 3;
                    else begin
                        error_code <= 0; test_pass <= 0;
                        result_address <= command_address; expected_data <= 0;
                        if (opcode == 4) begin
                            test_base <= command_address; test_index <= 0;
                            state <= TEST_WRITE;
                        end else if (opcode == 6) begin
                            result_data <= pin_levels; expected_data <= pin_activity;
                            result_address <= clock_edges;
                        end else if (opcode == 5) begin
                            // Cached ID: read-ID is only valid immediately after reset.
                            result_address <= device_id; result_data <= device_id[7:0];
                        end else begin
                            operation <= opcode == 3 ? 2 : (opcode == 2 ? 1 : 0);
                            address <= command_address; write_data <= command_data;
                            request <= 1; state <= WAIT_OP;
                        end
                    end
                end
                WAIT_OP: if (ram_done) begin
                    result_data <= read_data;
                    if (operation == 2) result_address <= device_id;
                    state <= IDLE;
                end
                TEST_WRITE: if (!ram_busy) begin
                    operation <= 1; address <= test_address;
                    write_data <= test_pattern;
                    request <= 1; state <= TEST_WRITE_WAIT;
                end
                TEST_WRITE_WAIT: if (ram_done) begin
                    if (test_index == 255) begin test_index <= 0; state <= TEST_READ; end
                    else begin test_index <= test_index + 1'b1; state <= TEST_WRITE; end
                end
                TEST_READ: if (!ram_busy) begin
                    operation <= 0; address <= test_address;
                    request <= 1; state <= TEST_READ_WAIT;
                end
                TEST_READ_WAIT: if (ram_done) begin
                    result_address <= address; result_data <= read_data;
                    expected_data <= address_pattern;
                    if (read_data != address_pattern) begin error_code <= 4; state <= IDLE; end
                    else if (test_index == 255) begin test_pass <= 1; state <= IDLE; end
                    else begin test_index <= test_index + 1'b1; state <= TEST_READ; end
                end
            endcase
        end
    end
endmodule
