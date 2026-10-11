`timescale 1ns/1ps
// Behavioral protocol model, not a vendor timing model. Checks CE# duration,
// address framing, reset-before-ID, and ID/read/write bit alignment.
module aps6404_model(
    input wire cs_n, input wire sck, inout wire [3:0] dq,
    input wire corrupt_reads
);
    reg [7:0] memory [0:8388607];
    reg [7:0] shift, command;
    reg [23:0] address;
    integer count;
    reg miso, drive_miso, reset_enabled, id_allowed, qpi_mode;
    reg [7:0] qpi_shift;
    time selected_at, deselected_at;
    integer transactions, writes, reads;
    assign dq[1] = drive_miso ? miso : 1'bz;
    assign dq[3:2] = 2'bzz;
    assign dq[0] = 1'bz;
    initial begin
        count=0; shift=0; command=0; address=0; miso=0; drive_miso=0;
        reset_enabled=0; id_allowed=0; qpi_mode=0; qpi_shift=0;
        selected_at=0; deselected_at=0; transactions=0; writes=0; reads=0;
    end
    always @(negedge cs_n) begin
        if ($time > 1000 && $time-deselected_at < 50)
            $fatal(1,"CE# high interval shorter than 50 ns");
        count=0; shift=0; command=0; address=0; qpi_shift=0;
        drive_miso=0; selected_at=$time;
    end
    always @(posedge cs_n) begin
        if (selected_at != 0 && $time-selected_at > 8000)
            $fatal(1,"CE# low exceeds refresh limit: %0t",$time-selected_at);
        drive_miso=0; deselected_at=$time;
        if (count != 0) transactions=transactions+1;
        if (count >= 8 && command == 8'h66) reset_enabled=1;
        else if (count >= 8 && command == 8'h99 && reset_enabled) begin
            reset_enabled=0; id_allowed=1; qpi_mode=0;
        end else if (count >= 8) reset_enabled=0;
    end
    always @(posedge sck) if (!cs_n) begin
        if (qpi_mode) begin
            qpi_shift={qpi_shift[3:0],dq};
            count=count+4;
            if (count == 8 && qpi_shift == 8'hf5) qpi_mode=0;
        end else begin
            shift={shift[6:0],dq[0]};
            if (count == 7) begin
                command=shift;
                if (command == 8'h9f && !id_allowed)
                    $fatal(1,"ID requested without reset");
                if (command == 8'h03 || command == 8'h02) id_allowed=0;
            end
            if (count >= 8 && count < 32) address={address[22:0],dq[0]};
            if (count >= 32 && command == 8'h02 && (count-32)%8 == 7) begin
                if (address >= 8388608) $fatal(1,"Out-of-range write");
                memory[address]=shift; address=address+1; writes=writes+1;
            end
            count=count+1;
        end
    end
    always @(negedge sck) if (!cs_n && !qpi_mode && count >= 32) begin
        if (command == 8'h03) begin
            if (address >= 8388608) $fatal(1,"Out-of-range read");
            drive_miso=1;
            miso=memory[address][7-((count-32)%8)] ^ corrupt_reads;
            if ((count-32)%8 == 0) reads=reads+1;
            // Increment after the eighth data sampling edge, before next byte.
            if (count > 32 && (count-32)%8 == 0) begin
                address=(address+1)&24'h7fffff;
                miso=memory[address][7] ^ corrupt_reads;
            end
        end else if (command == 8'h9f && count < 56) begin
            drive_miso=1;
            case ((count-32)/8)
                0: miso=(8'h0d >> (7-((count-32)%8))) & 1;
                1: miso=(8'h5d >> (7-((count-32)%8))) & 1;
                2: miso=(8'h26 >> (7-((count-32)%8))) & 1;
            endcase
        end else drive_miso=0;
    end
endmodule
