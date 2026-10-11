`timescale 1ns/1ps
module psram_demo #(
    parameter POWERUP_CYCLES=20000, parameter ENABLE_QPI=0,
    parameter QPI_HALF_PERIOD=2, parameter BURST_BYTES=32, parameter SYS_KHZ=51666,
    parameter INIT_HALF_PERIOD=2, parameter TRACE=0,
    parameter SPI_BURST=0, parameter SPI_FAST_READ=0
)(
    input wire clk, input wire reset, input wire test_button,
    input wire host_sck, input wire host_mosi, input wire host_cs_n,
    output wire host_miso, output wire ram_cs_n, output wire ram_sck,
    input wire ram_cs_sense, input wire ram_sck_sense,
    input wire [3:0] ram_dq_in, output wire [3:0] ram_dq_out,
    output wire [3:0] ram_dq_oe, output wire [7:0] status_led
);
    wire command_valid;
    wire [7:0] opcode, command_data;
    wire [23:0] command_address;
    reg request, q_start;
    reg [1:0] operation;
    reg [23:0] address;
    reg [7:0] write_data;
    wire init_busy, ram_ready, ram_done, qpi_mode;
    wire [7:0] read_data;
    wire [23:0] device_id;
    wire init_cs_n, init_sck;
    wire [3:0] init_out, init_oe;
    wire q_busy, q_done, q_rx_valid, q_cs_n, q_sck;
    wire [7:0] q_tx_index, q_rx_index, q_rx_data;
    wire [3:0] q_out, q_oe;
    wire [31:0] trace_word;
    localparam IDLE=0, WAIT_OP=1, TEST_WRITE=2, TEST_WRITE_WAIT=3,
               TEST_READ=4, TEST_READ_WAIT=5, WAIT_QPI=6,
               QB_WRITE=7, QB_WRITE_WAIT=8, QB_READ=9, QB_READ_WAIT=10;
    localparam [16:0] QB_STEP=BURST_BYTES[16:0];
    localparam [8:0] QB_LENGTH=BURST_BYTES[8:0];
    localparam [23:0] CLOCK_KHZ=SYS_KHZ;
    localparam [23:0] SPI_KHZ=SYS_KHZ/(2*QPI_HALF_PERIOD);
    localparam STREAMING = ENABLE_QPI != 0 || SPI_BURST != 0;
    reg [3:0] state;
    reg [23:0] test_base, result_address;
    reg [16:0] test_index, test_length;
    reg [7:0] result_data, expected_data, error_code, test_seed;
    reg test_pass;
    reg [23:0] elapsed_cycles, write_cycles, read_cycles;
    wire occupied = init_busy || q_busy || state != IDLE;
    wire id_good = ram_ready && device_id[15:8] == 8'h5d;
    wire [7:0] status = {2'b0,qpi_mode,id_good,(error_code != 0),test_pass,ram_ready,occupied};
    wire [63:0] response = {8'h50,status,result_data,expected_data,result_address,error_code};
    assign status_led = status;
    assign ram_cs_n = q_busy ? q_cs_n : init_cs_n;
    assign ram_sck = q_busy ? q_sck : init_sck;
    assign ram_dq_out = q_busy ? q_out : init_out;
    assign ram_dq_oe = q_busy ? q_oe : init_oe;
    wire [23:0] test_address = test_base + {7'b0,test_index};
    wire [7:0] test_pattern = test_address[7:0] ^ test_address[15:8] ^ test_address[23:16] ^ test_seed;
    wire [7:0] address_pattern = address[7:0] ^ address[15:8] ^ address[23:16] ^ test_seed;
    wire [23:0] q_tx_address = address + {16'b0,q_tx_index};
    wire [7:0] q_pattern = q_tx_address[7:0] ^ q_tx_address[15:8] ^ q_tx_address[23:16] ^ test_seed;
    wire [23:0] q_rx_address = address + {16'b0,q_rx_index};
    wire [7:0] q_expected = q_rx_address[7:0] ^ q_rx_address[15:8] ^ q_rx_address[23:16] ^ test_seed;
    wire [16:0] requested_length = 17'd1 << command_data[4:0];
    reg [16:0] accepted_length;
    reg [1:0] command_pipe;
    reg command_range_bad;
    wire [24:0] requested_end = {1'b0,command_address} + {8'b0,accepted_length};
    // Host fields remain stable between slow frames. Pipeline bounds checking
    // so the variable size/adder does not feed every FSM result register.
    always @(posedge clk) begin
        if (reset) begin accepted_length <= 0; command_pipe <= 0; command_range_bad <= 0; end
        else begin
            command_pipe <= {command_pipe[0],command_valid};
            if (command_valid) accepted_length <= requested_length;
            if (command_pipe[0]) command_range_bad <= command_address[23] ||
                (opcode == 4 && command_address > 24'h7fff00) ||
                (opcode == 7 && (command_data[4:0] < 8 || command_data[4:0] > 16 ||
                                requested_end > 25'h0800000));
        end
    end
    reg [7:0] pin_activity;
    reg [23:0] clock_edges;
    reg previous_sck;
    wire [7:0] pin_levels = {2'b0,ram_cs_sense,ram_sck_sense,ram_dq_in};
    always @(posedge clk) begin
        previous_sck <= ram_sck_sense;
        if (reset) begin pin_activity <= 0; clock_edges <= 0; previous_sck <= 0; end
        else begin
            if (ram_cs_sense) pin_activity[1] <= 1;
            else begin
                pin_activity[0] <= 1;
                if (ram_sck_sense) pin_activity[3] <= 1; else pin_activity[2] <= 1;
                if (ram_dq_in[0]) pin_activity[5] <= 1; else pin_activity[4] <= 1;
                if (!ram_dq_oe[1]) begin
                    if (ram_dq_in[1]) pin_activity[7] <= 1; else pin_activity[6] <= 1;
                end
                if (ram_sck_sense && !previous_sck) clock_edges <= clock_edges+1'b1;
            end
        end
    end
    host_spi host(.clk(clk),.reset(reset),.sck(host_sck),.mosi(host_mosi),
        .cs_n(host_cs_n),.response(response),.miso(host_miso),
        .command_valid(command_valid),.opcode(opcode),.address(command_address),.data(command_data));
    psram_spi #(.POWERUP_CYCLES(POWERUP_CYCLES),.ENABLE_QPI(ENABLE_QPI),
        .INIT_HALF_PERIOD(INIT_HALF_PERIOD)) ram(
        .clk(clk),.reset(reset),.request(request),.operation(operation),
        .address(address),.write_data(write_data),.busy(init_busy),.ready(ram_ready),
        .done(ram_done),.qpi_mode(qpi_mode),.read_data(read_data),.device_id(device_id),
        .cs_n(init_cs_n),.sck(init_sck),.dq_in(ram_dq_in),.dq_out(init_out),.dq_oe(init_oe));
    generate if (ENABLE_QPI != 0 || SPI_BURST == 0) begin: quad_engine
    qpi_burst #(.HALF_PERIOD(QPI_HALF_PERIOD),.TRACE(TRACE)) burst(
        .clk(clk),.reset(reset),.start(q_start),.write(operation == 1),
        .address(address),.length(state == WAIT_QPI ? 9'd1 : QB_LENGTH),
        .tx_index(q_tx_index),.tx_data(state == WAIT_QPI ? write_data : q_pattern),
        .rx_valid(q_rx_valid),.rx_index(q_rx_index),.rx_data(q_rx_data),
        .dq_in(ram_dq_in),.dq_out(q_out),.dq_oe(q_oe),
        .cs_n(q_cs_n),.sck(q_sck),.busy(q_busy),.done(q_done),
        .sck_pad(ram_sck_sense),.trace_index(command_data[4:0]),.trace_word(trace_word));
    end else begin: serial_engine
    spi_burst #(.HALF_PERIOD(QPI_HALF_PERIOD),.FAST_READ(SPI_FAST_READ)) burst(
        .clk(clk),.reset(reset),.start(q_start),.write(operation == 1),
        .address(address),.length(state == WAIT_QPI ? 9'd1 : QB_LENGTH),
        .tx_index(q_tx_index),.tx_data(state == WAIT_QPI ? write_data : q_pattern),
        .rx_valid(q_rx_valid),.rx_index(q_rx_index),.rx_data(q_rx_data),
        .dq_in(ram_dq_in),.dq_out(q_out),.dq_oe(q_oe),
        .cs_n(q_cs_n),.sck(q_sck),.busy(q_busy),.done(q_done),
        .sck_pad(ram_sck_sense),.trace_index(command_data[4:0]),.trace_word(trace_word));
    end endgenerate
    always @(posedge clk) begin
        request <= 0; q_start <= 0;
        if (reset) begin
            state <= IDLE; request <= 0; q_start <= 0; operation <= 0; address <= 0;
            write_data <= 0; test_base <= 0; test_index <= 0; test_length <= 256;
            result_address <= 0; result_data <= 0; expected_data <= 0;
            error_code <= 0; test_pass <= 0; test_seed <= 8'ha5;
            elapsed_cycles <= 0; write_cycles <= 0; read_cycles <= 0;
        end else begin
            if (state >= TEST_WRITE && state != WAIT_QPI) elapsed_cycles <= elapsed_cycles+1'b1;
            case (state)
                IDLE: if (!init_busy && ram_ready && test_button) begin
                    test_base <= 0; test_index <= 0; test_length <= 256; test_seed <= 8'ha5;
                    test_pass <= 0; error_code <= 0;
                    elapsed_cycles <= 0; write_cycles <= 0; read_cycles <= 0;
                    state <= STREAMING ? QB_WRITE : TEST_WRITE;
                end else if (command_pipe[1] && opcode != 0) begin
                    if (init_busy) error_code <= 1;
                    else if (opcode > 9) error_code <= 2;
                    else if (command_range_bad) error_code <= 3;
                    else begin
                        error_code <= 0;
                        if (opcode != 6 && opcode != 8 && opcode != 9) test_pass <= 0;
                        result_address <= command_address; expected_data <= 0;
                        if (opcode == 4 || opcode == 7) begin
                            test_base <= command_address; test_index <= 0;
                            test_length <= opcode == 4 ? 17'd256 : accepted_length;
                            test_seed <= opcode == 4 ? 8'ha5 : {command_data[7:5],5'b10101};
                            elapsed_cycles <= 0; write_cycles <= 0; read_cycles <= 0;
                            state <= STREAMING ? QB_WRITE : TEST_WRITE;
                        end else if (opcode == 9) begin
                            result_address <= trace_word[23:0]; result_data <= trace_word[31:24];
                        end else if (opcode == 8) begin
                            case (command_data)
                                0: result_address <= write_cycles;
                                1: result_address <= read_cycles;
                                2: result_address <= {7'b0,test_length};
                                3: result_address <= CLOCK_KHZ;
                                4: result_address <= STREAMING ? {15'b0,QB_LENGTH} : 24'd1;
                                5: result_address <= STREAMING ? SPI_KHZ : CLOCK_KHZ/(2*INIT_HALF_PERIOD);
                                default: error_code <= 2;
                            endcase
                        end else if (opcode == 6) begin
                            result_data <= pin_levels; expected_data <= pin_activity; result_address <= clock_edges;
                        end else if (opcode == 5) begin
                            result_address <= device_id; result_data <= device_id[7:0];
                        end else begin
                            operation <= opcode == 3 ? 2 : (opcode == 2 ? 1 : 0);
                            address <= command_address; write_data <= command_data;
                            if (STREAMING && opcode != 3) begin q_start <= 1; state <= WAIT_QPI; end
                            else begin request <= 1; state <= WAIT_OP; end
                        end
                    end
                end
                WAIT_OP: if (ram_done) begin
                    result_data <= read_data;
                    if (operation == 2) result_address <= device_id;
                    state <= IDLE;
                end
                WAIT_QPI: if (q_done) begin result_data <= q_rx_data; state <= IDLE; end
                TEST_WRITE: if (!init_busy) begin
                    operation <= 1; address <= test_address; write_data <= test_pattern;
                    request <= 1; state <= TEST_WRITE_WAIT;
                end
                TEST_WRITE_WAIT: if (ram_done) begin
                    if (test_index+17'd1 == test_length) begin
                        test_index <= 0; write_cycles <= elapsed_cycles+1'b1; state <= TEST_READ;
                    end else begin test_index <= test_index+1'b1; state <= TEST_WRITE; end
                end
                TEST_READ: if (!init_busy) begin
                    operation <= 0; address <= test_address; request <= 1; state <= TEST_READ_WAIT;
                end
                TEST_READ_WAIT: if (ram_done) begin
                    result_address <= address; result_data <= read_data; expected_data <= address_pattern;
                    if (read_data != address_pattern) begin error_code <= 4; state <= IDLE; end
                    else if (test_index+17'd1 == test_length) begin
                        test_pass <= 1; read_cycles <= elapsed_cycles+1'b1-write_cycles; state <= IDLE;
                    end else begin test_index <= test_index+1'b1; state <= TEST_READ; end
                end
                QB_WRITE: begin operation <= 1; address <= test_address; q_start <= 1; state <= QB_WRITE_WAIT; end
                QB_WRITE_WAIT: if (q_done) begin
                    if (test_index+QB_STEP == test_length) begin
                        test_index <= 0; write_cycles <= elapsed_cycles+1'b1; state <= QB_READ;
                    end else begin test_index <= test_index+QB_STEP; state <= QB_WRITE; end
                end
                QB_READ: begin operation <= 0; address <= test_address; q_start <= 1; state <= QB_READ_WAIT; end
                QB_READ_WAIT: begin
                    if (q_rx_valid && error_code == 0) begin
                        result_address <= q_rx_address; result_data <= q_rx_data; expected_data <= q_expected;
                        if (q_rx_data != q_expected) error_code <= 4;
                    end
                    if (q_done) begin
                        if (error_code != 0) state <= IDLE;
                        else if (test_index+QB_STEP == test_length) begin
                            test_pass <= 1; read_cycles <= elapsed_cycles+1'b1-write_cycles; state <= IDLE;
                        end else begin test_index <= test_index+QB_STEP; state <= QB_READ; end
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
