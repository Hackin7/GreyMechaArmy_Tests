// Eight raw RGB565 words from centers of the first line's color-bar cells.
// Bundled data stays immutable until the system-domain acknowledge returns.
module camera_color_probe(
    input wire pclk,presetn,clk,resetn,write_enable,frame_toggle,
    input wire [14:0] write_address,
    input wire [15:0] write_data,
    output reg [127:0] samples
);
    reg [127:0] scratch,payload;
    reg [7:0] seen;
    reg previous_frame,request,ack;
    (* async_reg="true" *) reg [1:0] ack_sync,request_sync;
    always @(posedge pclk or negedge presetn) begin
        if(!presetn) begin
            scratch<=0;payload<=0;seen<=0;previous_frame<=0;request<=0;ack_sync<=0;
        end else begin
            ack_sync<={ack_sync[0],ack};
            if(write_enable) case(write_address)
                10:begin scratch[127:112]<=write_data;seen[0]<=1;end
                30:begin scratch[111:96]<=write_data;seen[1]<=1;end
                50:begin scratch[95:80]<=write_data;seen[2]<=1;end
                70:begin scratch[79:64]<=write_data;seen[3]<=1;end
                90:begin scratch[63:48]<=write_data;seen[4]<=1;end
                110:begin scratch[47:32]<=write_data;seen[5]<=1;end
                130:begin scratch[31:16]<=write_data;seen[6]<=1;end
                150:begin scratch[15:0]<=write_data;seen[7]<=1;end
            endcase
            if(frame_toggle!=previous_frame) begin
                previous_frame<=frame_toggle;seen<=0;
                if(&seen && request==ack_sync[1]) begin payload<=scratch;request<=!request;end
            end
        end
    end
    always @(posedge clk) begin
        if(!resetn) begin request_sync<=0;ack<=0;samples<=0;end
        else begin
            request_sync<={request_sync[0],request};
            if(request_sync[1]!=ack) begin samples<=payload;ack<=request_sync[1];end
        end
    end
endmodule
