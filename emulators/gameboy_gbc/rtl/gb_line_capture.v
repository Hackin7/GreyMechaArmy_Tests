module gb_line_capture (
    input  wire        core_clk,
    input  wire        core_reset,
    input  wire        pixel_valid,
    input  wire [15:0] pixel_rgb565,
    input  wire        frame_sync,
    input  wire        panel_clk,
    input  wire        panel_reset,
    input  wire [7:0]  panel_rd_addr,
    input  wire        panel_rd_bank,
    output reg  [15:0] panel_rd_data,
    output reg         panel_line_ready,
    output reg         panel_line_bank,
    output reg  [7:0]  panel_line_number,
    input  wire        panel_line_done,
    output reg         overflow
);
    reg [15:0] pixels [0:319];
    reg [7:0] x;
    reg [7:0] line_no;
    reg write_bank;
    reg publish_bank;
    reg [7:0] publish_line;
    reg publish_toggle;
    reg frame_sync_d;
    reg ack_toggle;
    reg ack_s1, ack_s2;
    reg pub_s1, pub_s2, pub_seen;
    reg bank_s1, bank_s2;
    reg [7:0] line_s1, line_s2;

    always @(posedge core_clk) begin
        ack_s1 <= ack_toggle;
        ack_s2 <= ack_s1;
        frame_sync_d <= frame_sync;
        if (core_reset) begin
            x <= 0; line_no <= 0; write_bank <= 0;
            publish_bank <= 0; publish_line <= 0; publish_toggle <= 0;
            frame_sync_d <= 0; overflow <= 0;
        end else begin
            if (frame_sync && !frame_sync_d) begin
                x <= 0;
                line_no <= 0;
            end
            if (pixel_valid) begin
                pixels[(write_bank ? 9'd160 : 9'd0) + x] <= pixel_rgb565;
                if (x == 8'd159) begin
                    if (ack_s2 != publish_toggle) overflow <= 1'b1;
                    publish_bank <= write_bank;
                    publish_line <= line_no;
                    publish_toggle <= ~publish_toggle;
                    write_bank <= ~write_bank;
                    x <= 0;
                    // VSync may coincide with this final-pixel branch, whose
                    // later nonblocking assignment would otherwise defeat the
                    // frame reset and leave the line number stuck at 143.
                    line_no <= (line_no == 8'd143) ? 8'd0 : line_no + 1'b1;
                end else x <= x + 1'b1;
            end
        end
    end

    always @(posedge panel_clk) begin
        panel_rd_data <= pixels[(panel_rd_bank ? 9'd160 : 9'd0) + panel_rd_addr];
        pub_s1 <= publish_toggle; pub_s2 <= pub_s1;
        bank_s1 <= publish_bank; bank_s2 <= bank_s1;
        line_s1 <= publish_line; line_s2 <= line_s1;
        if (panel_reset) begin
            pub_seen <= 0; ack_toggle <= 0; panel_line_ready <= 0;
            panel_line_bank <= 0; panel_line_number <= 0;
        end else begin
            if (pub_s2 != pub_seen) begin
                pub_seen <= pub_s2;
                panel_line_bank <= bank_s2;
                panel_line_number <= line_s2;
                panel_line_ready <= 1'b1;
            end
            if (panel_line_done) begin
                panel_line_ready <= 1'b0;
                ack_toggle <= pub_seen;
            end
        end
    end
endmodule
