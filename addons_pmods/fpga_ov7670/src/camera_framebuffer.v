// True dual-clock RAM. The two banks each hold exactly one 160x120 frame.
// request_toggle equals the completed bank (first completed bank is 1).
module camera_framebuffer #(
    parameter integer WIDTH=160, HEIGHT=120
)(
    input wire pclk,
    input wire write_enable, write_bank,
    input wire [14:0] write_address,
    input wire [15:0] write_data,
    input wire clk, resetn, request_toggle, frame_boundary,
    input wire [14:0] read_address,
    output reg [15:0] read_data,
    output reg ack_toggle,
    output reg valid,
    output wire frame_accepted
);
    (* ram_style = "block" *) reg [15:0] bank0 [0:WIDTH*HEIGHT-1];
    (* ram_style = "block" *) reg [15:0] bank1 [0:WIDTH*HEIGHT-1];
    (* async_reg = "true" *) reg [1:0] request_sync;
    reg read_bank;
    reg [15:0] q0, q1;
    reg [15:0] bank0_registered, bank1_registered;
    // No reset on RAM ports: retain ECP5 block-RAM inference.
    always @(posedge pclk) begin
        if (write_enable && !write_bank) bank0[write_address] <= write_data;
        if (write_enable && write_bank) bank1[write_address] <= write_data;
    end
    always @(posedge clk) begin
        q0 <= bank0[read_address]; q1 <= bank1[read_address];
        // Register each bank's depth mux before the bank-select mux. Keeping
        // these stages separate gives routing margin when camera pins move.
        bank0_registered <= q0; bank1_registered <= q1;
        read_data <= read_bank ? bank1_registered : bank0_registered;
    end
    assign frame_accepted = frame_boundary && request_sync[1] != ack_toggle;
    always @(posedge clk) begin
        if (!resetn) begin
            request_sync<=0; ack_toggle<=0; read_bank<=0; valid<=0;
        end else begin
            request_sync <= {request_sync[0],request_toggle};
            if (frame_accepted) begin
                read_bank<=request_sync[1]; ack_toggle<=request_sync[1]; valid<=1;
            end
        end
    end
endmodule
