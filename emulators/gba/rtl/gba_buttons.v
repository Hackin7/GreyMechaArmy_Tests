module gba_buttons #(
    parameter CLK_HZ=100000000, parameter DEBOUNCE_CYCLES=CLK_HZ/200,
    parameter START_CYCLES=CLK_HZ/20, parameter SHARED_DEBOUNCE=0
)(
    input wire clk,reset, input wire [4:0] btn_n,
    input wire grey_n,red_n,
    input wire inject_enable, input wire [9:0] injected,
    output wire [9:0] keys, output reg mode_toggle,
    output wire [6:0] physical
);
    localparam CW=$clog2(DEBOUNCE_CYCLES+1), SW=$clog2(START_CYCLES+1);
    reg [6:0] s1,s2,stable;
    reg center_d, up_d, consumed;
    reg [SW-1:0] start_count;
    wire center=stable[2];
    wire [9:0] mapped={center&&stable[5],center&&stable[6],
        stable[3],stable[1],stable[0],stable[4],
        (start_count!=0),center&&stable[3],
        stable[6]&&!center,stable[5]&&!center};
    // KEYINPUT order: A B Select Start Right Left Up Down R L.
    wire [9:0] cleaned=mapped & ~(center  ?  10'b0011000000 : 10'd0);
    assign keys=inject_enable  ?  injected : cleaned;
    assign physical=stable;
    generate if(SHARED_DEBOUNCE)begin: shared_filter
        // One timer accepts a whole stable button vector. A bounce on any
        // switch restarts the qualification interval for the whole vector.
        reg [6:0] candidate;
        reg [CW-1:0] count;
        always @(posedge clk)begin
            if(reset)begin stable<=0;candidate<=0;count<=0;end
            else if(s2!=candidate)begin candidate<=s2;count<=0;end
            else if(candidate==stable)count<=0;
            else if(count==DEBOUNCE_CYCLES-1)begin stable<=candidate;count<=0;end
            else count<=count+1'b1;
        end
    end else begin: independent_filters
        reg [CW-1:0] counts[0:6];integer b;
        always @(posedge clk)begin
            if(reset)begin stable<=0;for(b=0;b<7;b=b+1)counts[b]<=0;end
            else for(b=0;b<7;b=b+1)begin
                if(s2[b]==stable[b])counts[b]<=0;
                else if(counts[b]==DEBOUNCE_CYCLES-1)begin stable[b]<=s2[b];counts[b]<=0;end
                else counts[b]<=counts[b]+1'b1;
            end
        end
    end endgenerate
    always @(posedge clk) begin
        s1<=~{red_n,grey_n,btn_n};s2<=s1;
        if(reset) begin
            s1<=0;s2<=0;center_d<=0;up_d<=0;consumed<=0;
            mode_toggle<=0;start_count<=0;
        end else begin
            center_d<=center;up_d<=stable[1];
            if(start_count!=0) start_count<=start_count-1'b1;
            if(center&&!center_d) consumed<=0;
            if(center&&(stable[5]||stable[6]||stable[3]||stable[1])) consumed<=1;
            if(center && stable[1] && (!up_d||!center_d)) mode_toggle<=~mode_toggle;
            if(!center&&center_d&&!consumed) start_count<=START_CYCLES;
        end
    end
endmodule
