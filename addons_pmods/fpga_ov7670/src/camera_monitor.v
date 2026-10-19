// Independent activity/geometry monitor, sampled well above the divided PCLK.
// DVP control inputs use equal synchronizer depth. No pixel data is sampled.
module camera_monitor(
    input wire clk, resetn, pclk, href, vsync,
    output reg [31:0] pclk_edges, frames,
    output reg [9:0] last_lines,
    output reg [11:0] last_bytes
);
    (* async_reg="true" *) reg [2:0] p_sync,h_sync,v_sync;
    reg [9:0] lines;
    reg [11:0] bytes_in_line;
    always @(posedge clk) begin
        if(!resetn) begin
            p_sync<=0;h_sync<=0;v_sync<=0;pclk_edges<=0;frames<=0;
            lines<=0;bytes_in_line<=0;last_lines<=0;last_bytes<=0;
        end else begin
            p_sync<={p_sync[1:0],pclk};h_sync<={h_sync[1:0],href};v_sync<={v_sync[1:0],vsync};
            if(p_sync[2:1]==2'b01) begin
                pclk_edges<=pclk_edges+1'b1;
                if(h_sync[2] && !(&bytes_in_line)) bytes_in_line<=bytes_in_line+1'b1;
            end
            if(h_sync[2:1]==2'b10) begin
                last_bytes<=bytes_in_line;bytes_in_line<=0;
                if(!v_sync[2] && !(&lines)) lines<=lines+1'b1;
            end
            if(v_sync[2:1]==2'b01) begin
                frames<=frames+1'b1;last_lines<=lines;lines<=0;
            end
        end
    end
endmodule
