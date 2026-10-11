module gc9a01_native (
    input wire clk, input wire resetn,
    input wire line_ready, input wire line_bank, input wire [7:0] line_number,
    output wire line_done, output wire [7:0] rd_addr, output wire rd_bank,
    input wire [15:0] rd_data,
    output wire sclk, output wire mosi, output wire dc,
    output wire cs_n, output wire rst_n
);
    wire init_done, ramwr_pulse;
    wire i_sclk, i_mosi, i_dc, i_cs, i_rst;
    wire s_sclk, s_mosi, s_dc, s_cs, frame_done;
    reg init_owner;
    reg first_frame_started;

    gc9a01_window_init init (
        .clk(clk), .resetn(resetn), .rearm(frame_done),
        .init_done(init_done), .ramwr_pulse(ramwr_pulse),
        .sclk(i_sclk), .mosi(i_mosi), .dc(i_dc), .cs_n(i_cs), .rst_n(i_rst)
    );
    gc9a01_line_stream stream (
        .clk(clk), .resetn(resetn), .enable(init_done && !init_owner),
        .line_ready(line_ready), .line_bank(line_bank),
        .line_number(line_number), .line_done(line_done),
        .rd_addr(rd_addr), .rd_bank(rd_bank), .rd_data(rd_data),
        .frame_done(frame_done), .sclk(s_sclk), .mosi(s_mosi),
        .dc(s_dc), .cs_n(s_cs)
    );

    always @(posedge clk) begin
        if (!resetn) begin
            init_owner <= 1'b1;
            first_frame_started <= 1'b0;
        end else if (frame_done) begin
            // Hold the panel pins on the init/rearm sequencer until it has
            // physically shifted the next RAMWR command.
            init_owner <= 1'b1;
        end else if (!first_frame_started && init_done) begin
            // Initial window setup already ends with RAMWR, but intentionally
            // does not pulse ramwr_pulse.  Release once for the white frame.
            first_frame_started <= 1'b1;
            init_owner <= 1'b0;
        end else if (ramwr_pulse) begin
            init_owner <= 1'b0;
        end
    end
    assign sclk = init_owner ? i_sclk : s_sclk;
    assign mosi = init_owner ? i_mosi : s_mosi;
    assign dc   = init_owner ? i_dc   : s_dc;
    assign cs_n = init_owner ? i_cs   : s_cs;
    assign rst_n = i_rst;
endmodule
