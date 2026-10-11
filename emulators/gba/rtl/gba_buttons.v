module gba_buttons #(
    parameter CLK_HZ=100000000, parameter DEBOUNCE_CYCLES=CLK_HZ/200,
    parameter START_CYCLES=CLK_HZ/20
)(
    input wire clk,reset, input wire [4:0] btn_n,
    input wire grey_n,red_n,
    input wire inject_enable, input wire [9:0] injected,
    output wire [9:0] keys, output reg mode_toggle,
    output wire [6:0] physical
);
    localparam CW=$clog2(DEBOUNCE_CYCLES+1), SW=$clog2(START_CYCLES+1);
    reg [6:0] s1,s2,stable;
    reg [CW-1:0] counts[0:6];
    reg center_d, up_d, consumed;
    reg [SW-1:0] start_count;
    integer i;
    wire center=stable[2];
    wire [9:0] mapped={center&&stable[5],center&&stable[6],
        stable[3],stable[1],stable[0],stable[4],
        (start_count!=0),center&&stable[3],
        stable[6]&&!center,stable[5]&&!center};
    // KEYINPUT order: A B Select Start Right Left Up Down R L.
    wire [9:0] cleaned=mapped & ~(center  ?  10'b0011000000 : 10'd0);
    assign keys=inject_enable  ?  injected : cleaned;
    assign physical=stable;
    always @(posedge clk) begin
        s1<=~{red_n,grey_n,btn_n};s2<=s1;
        if(reset) begin
            s1<=0;s2<=0;stable<=0;center_d<=0;up_d<=0;consumed<=0;
            mode_toggle<=0;start_count<=0;
            for(i=0;i<7;i=i+1) counts[i]<=0;
        end else begin
            for(i=0;i<7;i=i+1) begin
                if(s2[i]==stable[i]) counts[i]<=0;
                else if(counts[i]==DEBOUNCE_CYCLES-1) begin stable[i]<=s2[i];counts[i]<=0;end
                else counts[i]<=counts[i]+1'b1;
            end
            center_d<=center;up_d<=stable[1];
            if(start_count!=0) start_count<=start_count-1'b1;
            if(center&&!center_d) consumed<=0;
            if(center&&(stable[5]||stable[6]||stable[3]||stable[1])) consumed<=1;
            if(center && stable[1] && (!up_d||!center_d)) mode_toggle<=~mode_toggle;
            if(!center&&center_d&&!consumed) start_count<=START_CYCLES;
        end
    end
endmodule
