// Passive monitor: never drives camera outputs. Counts sampled rising edges
// modulo 65536 and remembers any transition after synchronizer settling.
module camera_pin_monitor(
    input wire clk, resetn,
    input wire [11:0] pins,
    output wire [191:0] counts,
    output wire [11:0] levels,
    output reg [11:0] changed
);
    (* async_reg="true" *) reg [11:0] meta,sync;
    reg [11:0] previous;
    reg [2:0] settled;
    reg [15:0] edges[0:11];
    assign levels=sync;
    genvar g;
    generate for(g=0;g<12;g=g+1) begin: pack
        assign counts[g*16+:16]=edges[g];
    end endgenerate
    integer i;
    always @(posedge clk) begin
        if(!resetn) begin
            meta<=0;sync<=0;previous<=0;changed<=0;settled<=0;
            for(i=0;i<12;i=i+1) edges[i]<=0;
        end else begin
            meta<=pins;sync<=meta;previous<=sync;
            settled<={settled[1:0],1'b1};
            if(settled[2]) begin
                changed<=changed|(sync^previous);
                for(i=0;i<12;i=i+1)
                    if(sync[i] && !previous[i]) edges[i]<=edges[i]+1'b1;
            end
        end
    end
endmodule
