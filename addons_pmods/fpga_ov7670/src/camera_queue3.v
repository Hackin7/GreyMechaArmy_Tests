// System-domain ownership. Pending images may be superseded, active display
// images are released only after the last SPI pixel has been transmitted.
module camera_queue3(
    input wire clk,resetn,
    input wire [2:0] ready_toggle,
    input wire display_start,display_done,
    output reg [2:0] release_toggle,
    output reg pending_valid,display_busy,
    output reg [1:0] read_bank,
    output reg valid,
    output reg frame_accepted,
    output reg [31:0] replaced_frames
);
    (* async_reg="true" *) reg [2:0] ready_meta,ready_sync;
    reg [2:0] seen;
    reg [1:0] pending_bank;
    wire [2:0] arrivals=ready_sync^seen;
    wire [1:0] arrival_bank=arrivals[0] ? 0 : arrivals[1] ? 1 : 2;
    always @(posedge clk) begin
        frame_accepted<=0;
        if(!resetn) begin
            ready_meta<=0;ready_sync<=0;seen<=0;release_toggle<=0;
            pending_valid<=0;display_busy<=0;read_bank<=0;pending_bank<=0;
            valid<=0;replaced_frames<=0;
        end else begin
            ready_meta<=ready_toggle;ready_sync<=ready_meta;
            if(display_done && display_busy) begin
                release_toggle[read_bank]<=seen[read_bank];display_busy<=0;
            end else if(display_start && pending_valid && !display_busy) begin
                read_bank<=pending_bank;pending_valid<=0;display_busy<=1;
                valid<=1;frame_accepted<=1;
            end else if(|arrivals) begin
                seen[arrival_bank]<=ready_sync[arrival_bank];
                if(pending_valid) begin
                    release_toggle[pending_bank]<=seen[pending_bank];
                    replaced_frames<=replaced_frames+1'b1;
                end
                pending_bank<=arrival_bank;pending_valid<=1;
            end
        end
    end
endmodule
