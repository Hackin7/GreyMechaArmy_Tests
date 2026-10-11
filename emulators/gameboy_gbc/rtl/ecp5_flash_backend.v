// Core-facing flash backend. Requests use a bundled-address toggle handshake;
// received {offset, byte} records cross a Gray-pointer FIFO. All cache-facing
// signals belong exclusively to clk_core. Completion acknowledges a request
// only after the last FIFO byte has been presented to the cache write port.
module ecp5_flash_backend #(parameter FAST_SPI = 1) (
    input wire clk_core, input wire clk_fast, input wire reset,
    input wire start, input wire [22:0] line_address, output wire busy,
    output wire fill_begin, output wire [22:0] fill_address,
    output wire fill_we, output wire [7:0] fill_offset,
    output wire [7:0] fill_data, output wire fill_commit,
    output wire flash_clk, output wire flash_cs_n, output wire flash_mosi,
    input wire flash_miso
);
    generate if (!FAST_SPI) begin : slow
        ecp5_flash_reader reader (
            .clk(clk_core), .reset(reset), .start(start),
            .line_address(line_address), .fill_ready(1'b1), .busy(busy),
            .fill_begin(fill_begin), .fill_address(fill_address),
            .fill_we(fill_we), .fill_offset(fill_offset), .fill_data(fill_data),
            .fill_commit(fill_commit), .flash_clk(flash_clk),
            .flash_cs_n(flash_cs_n), .flash_mosi(flash_mosi), .flash_miso(flash_miso)
        );
    end else begin : fast
        // Asynchronous assertion, synchronous deassertion in the fast domain.
        (* async_reg = "true" *) reg [1:0] reset_fast_sync;
        always @(posedge clk_fast or posedge reset) begin
            if (reset) reset_fast_sync <= 2'b11;
            else reset_fast_sync <= {reset_fast_sync[0], 1'b0};
        end
        wire reset_fast = reset_fast_sync[1];
        reg request_toggle, active, wait_release, commit_pending;
        reg [22:0] held_address;
        reg begin_core, we_core, commit_core;
        reg [7:0] offset_core, data_core;
        (* async_reg = "true" *) reg req_s1, req_s2;
        reg req_seen, start_fast;
        reg [22:0] address_fast;
        wire reader_busy, byte_we, fifo_full, fifo_empty;
        wire [7:0] byte_offset, byte_data;
        wire [15:0] fifo_data;
        wire fifo_pop = active && !commit_pending && !fifo_empty;
        assign busy = active;
        assign fill_begin = begin_core;
        assign fill_address = held_address;
        assign fill_we = we_core;
        assign fill_offset = offset_core;
        assign fill_data = data_core;
        assign fill_commit = commit_core;
        always @(posedge clk_core) begin
            begin_core <= 0; we_core <= 0; commit_core <= 0;
            if (reset) begin
                request_toggle <= 0; active <= 0; wait_release <= 0;
                commit_pending <= 0; held_address <= 0;
                offset_core <= 0; data_core <= 0;
            end else begin
                if (!start) wait_release <= 0;
                if (start && !active && !wait_release) begin
                    held_address <= {line_address[22:8],8'h00};
                    request_toggle <= ~request_toggle;
                    active <= 1; wait_release <= 1; begin_core <= 1;
                end
                if (fifo_pop) begin
                    offset_core <= fifo_data[15:8];
                    data_core <= fifo_data[7:0]; we_core <= 1;
                    if (fifo_data[15:8] == 8'hff) commit_pending <= 1;
                end
                if (commit_pending) begin
                    commit_pending <= 0; commit_core <= 1; active <= 0;
                end
            end
        end
        always @(posedge clk_fast) begin
            start_fast <= 0;
            if (reset_fast) begin
                req_s1 <= 0; req_s2 <= 0; req_seen <= 0;
                address_fast <= 0;
            end else begin
                req_s1 <= request_toggle; req_s2 <= req_s1;
                if (req_s2 != req_seen && !reader_busy) begin
                    // held_address has been stable for two synchronizer
                    // cycles; it remains held until this line completes.
                    req_seen <= req_s2; address_fast <= held_address;
                    start_fast <= 1;
                end
            end
        end
        ecp5_flash_reader #(.SPI_CYCLES(4)) reader (
            .clk(clk_fast), .reset(reset_fast), .start(start_fast),
            .line_address(address_fast), .fill_ready(!fifo_full),
            .busy(reader_busy), .fill_begin(), .fill_address(),
            .fill_we(byte_we), .fill_offset(byte_offset), .fill_data(byte_data),
            .fill_commit(), .flash_clk(flash_clk), .flash_cs_n(flash_cs_n),
            .flash_mosi(flash_mosi), .flash_miso(flash_miso)
        );
        gb_flash_fifo fifo (
            .wr_clk(clk_fast), .wr_reset(reset_fast),
            .wr_en(byte_we), .wr_data({byte_offset,byte_data}), .full(fifo_full),
            .rd_clk(clk_core), .rd_reset(reset), .rd_en(fifo_pop),
            .rd_data(fifo_data), .empty(fifo_empty)
        );
    end endgenerate
endmodule
