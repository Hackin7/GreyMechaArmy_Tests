// Ready/valid RGB565 shifter. A shortage waits with SCLK low between pixels.
module isp_spi #(parameter PIXELS=19200)(
    input wire clk,resetn,enable,input wire valid,input wire [15:0] pixel,
    output wire take,output reg sclk,mosi,cs,output reg done,
    output reg [31:0] wait_cycles
);
    reg [15:0] shift;
    reg [14:0] remaining;
    reg [4:0] bits;
    reg active,finished,phase;
    wire advance=active && phase && bits==1 && remaining>1;
    wire load=enable && !finished && (!active || advance) && valid;
    assign take=load;
    always @(posedge clk) begin
        done<=0;
        if(!resetn) wait_cycles<=0;
        if(!resetn || !enable) begin
            sclk<=0;mosi<=0;cs<=1;active<=0;finished<=0;
            phase<=0;bits<=0;remaining<=PIXELS;
        end else if(load) begin
            shift<=pixel;mosi<=pixel[15];bits<=16;active<=1;cs<=0;sclk<=0;phase<=0;
            if(advance) remaining<=remaining-1'b1;
        end else if(active) begin
            if(!phase) begin sclk<=1;phase<=1;end
            else begin
                sclk<=0;phase<=0;
                if(bits==1) begin
                    if(remaining==1) begin
                        remaining<=0;active<=0;finished<=1;cs<=1;done<=1;
                    end else begin
                        remaining<=remaining-1'b1;active<=0;
                    end
                end else begin
                    bits<=bits-1'b1;shift<={shift[14:0],1'b0};mosi<=shift[14];
                end
            end
        end else if(!finished) begin
            sclk<=0;
            // Initial prefill is intentional; count only in-image starvation.
            if(!cs) wait_cycles<=wait_cycles+1'b1;
        end
    end
endmodule
