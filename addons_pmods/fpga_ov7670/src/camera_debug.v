// Read-only mode-0 SPI: CS low snapshots 32 bytes, MSB first, no MOSI.
// First four bytes are ASCII CAM2. Host SCK must be <= 1 MHz.
module camera_debug #(parameter integer STATUS_BITS=256)(
    input wire clk, resetn, sck, cs_n,
    input wire [STATUS_BITS-1:0] status,
    output wire miso
);
    (* async_reg="true" *) reg [2:0] sck_sync, cs_sync;
    reg [STATUS_BITS-1:0] shift;
    assign miso=shift[STATUS_BITS-1];
    always @(posedge clk) begin
        if (!resetn) begin sck_sync<=0; cs_sync<=7; shift<=0; end
        else begin
            sck_sync<={sck_sync[1:0],sck}; cs_sync<={cs_sync[1:0],cs_n};
            if(cs_sync[2] || cs_sync[2:1]==2'b10) shift<=status;
            else if(sck_sync[2:1]==2'b10) shift<={shift[STATUS_BITS-2:0],1'b0};
        end
    end
endmodule
