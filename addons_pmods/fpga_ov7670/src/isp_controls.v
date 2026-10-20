// Buttons: grey, left, right, up, down. Commit an atomic image snapshot.
module isp_controls #(parameter DEBOUNCE_CYCLES=1000000)(
    input wire clk,resetn,commit,
    input wire [4:0] buttons_n,
    output reg enabled,
    output reg [2:0] mode,
    output reg [39:0] presets,
    output wire [15:0] value_q8
);
    localparam CW=$clog2(DEBOUNCE_CYCLES+1);
    (* async_reg="true" *) reg [4:0] sync1,sync2;
    reg [4:0] stable,press;
    reg [CW-1:0] counts[0:4];
    reg pending_enabled;
    reg [2:0] pending_mode;
    reg [7:0] pending[0:4];
    integer i;
    wire [7:0] selected=presets >> (mode*8);
    function [15:0] gamma_value(input [7:0] index);
        case(index)
            0:gamma_value=128;1:gamma_value=160;2:gamma_value=192;
            3:gamma_value=224;4:gamma_value=256;5:gamma_value=320;
            6:gamma_value=384;7:gamma_value=448;default:gamma_value=512;
        endcase
    endfunction
    assign value_q8=mode==0 ? {selected,10'd0} : mode==1 ? gamma_value(selected) :
        mode==4 ? (16'd64+{selected,6'd0}) : {selected,5'd0};
    always @(posedge clk) begin
        if(!resetn) begin
            sync1<=31;sync2<=31;stable<=31;press<=0;
            for(i=0;i<5;i=i+1) counts[i]<=0;
            pending_enabled<=0;pending_mode<=0;enabled<=0;mode<=0;
            pending[0]<=4;pending[1]<=6;pending[2]<=10;pending[3]<=10;pending[4]<=3;
            presets<=40'h030a0a0604;
        end else begin
            sync1<=buttons_n;sync2<=sync1;press<=0;
            for(i=0;i<5;i=i+1) begin
                if(sync2[i]==stable[i]) counts[i]<=0;
                else if(counts[i]==DEBOUNCE_CYCLES-1) begin
                    stable[i]<=sync2[i];counts[i]<=0;press[i]<=!sync2[i];
                end else counts[i]<=counts[i]+1'b1;
            end
            if(press[0]) pending_enabled<=!pending_enabled;
            if(press[3] || press[4]) begin
                if(press[3] && !press[4]) pending_mode<=pending_mode==4 ? 0 : pending_mode+1'b1;
                if(press[4] && !press[3]) pending_mode<=pending_mode==0 ? 4 : pending_mode-1'b1;
            end else begin
                if(press[1] && !press[2] && pending[pending_mode]!=0)
                    pending[pending_mode]<=pending[pending_mode]-1'b1;
                if(press[2] && !press[1] && pending[pending_mode] <
                    (pending_mode==1 ? 8 : pending_mode==4 ? 15 : 16))
                    pending[pending_mode]<=pending[pending_mode]+1'b1;
            end
            if(commit) begin
                enabled<=pending_enabled;mode<=pending_mode;
                presets<={pending[4],pending[3],pending[2],pending[1],pending[0]};
            end
        end
    end
endmodule
