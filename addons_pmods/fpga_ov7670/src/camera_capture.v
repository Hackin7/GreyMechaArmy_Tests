// D/HREF/VSYNC are source-synchronous to PCLK; do not synchronize them
// individually. OV7670 default COM10 polarity: latch data on rising PCLK.
module camera_capture #(
    parameter integer WIDTH=160, HEIGHT=120
)(
    input wire pclk, resetn, configured,
    input wire [7:0] data,
    input wire href, vsync,
    input wire ack_toggle,
    output reg request_toggle,
    output reg write_enable,
    output reg write_bank,
    output reg [14:0] write_address,
    output reg [15:0] write_data,
    output reg malformed
);
    (* async_reg = "true" *) reg [1:0] ack_sync, config_sync;
    reg href_d, vsync_d;
    reg active, bad, byte_phase, waiting;
    reg bank;
    reg [7:0] high_byte;
    reg [9:0] bytes_in_line;
    reg [8:0] lines;
    reg [14:0] address;
    // Asynchronous assertion is essential when PCLK is absent at startup.
    always @(posedge pclk or negedge resetn) begin
        if (!resetn) begin
            ack_sync<=0; config_sync<=0; href_d<=0; vsync_d<=0;
            active<=0; bad<=0; byte_phase<=0; waiting<=0;
            bank<=1; request_toggle<=0; write_enable<=0;
            write_bank<=1; write_address<=0; write_data<=0;
            high_byte<=0; bytes_in_line<=0; lines<=0; address<=0;
            malformed<=0;
        end else begin
            ack_sync <= {ack_sync[0],ack_toggle};
            config_sync <= {config_sync[0],configured};
            href_d<=href; vsync_d<=vsync; write_enable<=0;
            if (waiting && ack_sync[1] == request_toggle) begin
                waiting<=0; bank<=!bank;
            end
            if (!config_sync[1]) begin
                active<=0; byte_phase<=0;
            end else if (vsync && !vsync_d) begin
                if (active) begin
                    if (!bad && !href && !href_d && !byte_phase &&
                        lines == HEIGHT && address == WIDTH*HEIGHT) begin
                        request_toggle <= !request_toggle; waiting<=1;
                    end else malformed<=1;
                end
                active<=0;
            end else if (!vsync && vsync_d) begin
                // Never start in the middle of a frame after ownership returns.
                active<=!waiting; bad<=0; byte_phase<=0;
                bytes_in_line<=0; lines<=0; address<=0;
            end else if (active && !vsync) begin
                if (href) begin
                    if (lines >= HEIGHT || bytes_in_line >= WIDTH*2) bad<=1;
                    if (bytes_in_line < WIDTH*2+1)
                        bytes_in_line<=bytes_in_line+1'b1;
                    byte_phase<=!byte_phase;
                    if (!byte_phase) high_byte<=data;
                    else if (!bad && lines < HEIGHT && bytes_in_line < WIDTH*2) begin
                        write_enable<=1; write_bank<=bank;
                        write_address<=address; write_data<={high_byte,data};
                        if (address < WIDTH*HEIGHT) address<=address+1'b1;
                    end
                end else if (href_d) begin
                    if (bytes_in_line != WIDTH*2 || byte_phase) bad<=1;
                    if (lines < HEIGHT+1) lines<=lines+1'b1;
                    bytes_in_line<=0; byte_phase<=0;
                end
            end
        end
    end
endmodule
