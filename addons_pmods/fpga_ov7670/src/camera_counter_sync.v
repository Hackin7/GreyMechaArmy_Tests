module camera_counter_sync(
    input wire source_clk,source_resetn,clk,resetn,
    input wire [31:0] binary,
    output reg [31:0] value
);
    reg [31:0] gray;
    (* async_reg="true" *) reg [31:0] meta,sync;
    integer i;
    always @(posedge source_clk or negedge source_resetn)
        if(!source_resetn) gray<=0;
        else gray<=binary^(binary>>1);
    always @(posedge clk) begin
        if(!resetn) begin meta<=0;sync<=0;value<=0;end
        else begin
            meta<=gray;sync<=meta;
            value[31]<=sync[31];
            for(i=0;i<31;i=i+1) value[i]<=^(sync>>i);
        end
    end
endmodule
