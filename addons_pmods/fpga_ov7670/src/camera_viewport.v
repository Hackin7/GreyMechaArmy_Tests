module camera_viewport(
    input wire clk, resetn,
    input wire [15:0] pixel_index,
    input wire [15:0] ram_data,
    input wire frame_valid, enabled,
    input wire [6:0] offset,
    output wire [14:0] ram_address,
    output reg [15:0] pixel_data
);
    // The streamer requests monotonically increasing pixels and prefetches
    // six clocks before loading the next word. Track coordinates one clock
    // behind its request instead of putting division by 240 on the RAM path.
    reg [15:0] previous_index;
    reg [7:0] x, y;
    always @(posedge clk) begin
        if (!resetn) begin previous_index<=0; x<=0; y<=0; end
        else begin
            previous_index<=pixel_index;
            if (pixel_index==0) begin x<=0; y<=0; end
            else if (pixel_index!=previous_index) begin
                if (x==239) begin x<=0; y<=y+1'b1; end
                else x<=x+1'b1;
            end
        end
    end
    wire image_active = x >= 40 && x < 200 && y >= 60 && y < 180;
    wire [7:0] image_y = y - 8'd60;
    wire [7:0] image_x = x - 8'd40;
    wire [14:0] row_offset = {image_y,7'b0} + {2'b0,image_y,5'b0};
    assign ram_address = image_active ? row_offset + {7'b0,image_x} : 15'd0;
    reg inside_d, inside_dd, inside_ddd;
    wire [15:0] fallback = image_x<40 ? 16'hf800 : image_x<80 ? 16'h07e0 :
        image_x<120 ? 16'h001f : 16'hffff;
    reg [15:0] fallback_d,fallback_dd,fallback_ddd;
    wire [15:0] corrected;
    rgb_offset correction(.pixel(ram_data),.enabled(enabled),.offset(offset),
                          .corrected(corrected));
    always @(posedge clk) begin
        if (!resetn) begin
            inside_d<=0; inside_dd<=0; inside_ddd<=0; pixel_data<=0;
            fallback_d<=0;fallback_dd<=0;fallback_ddd<=0;
        end
        else begin
            inside_d<=image_active;
            inside_dd<=inside_d;
            inside_ddd<=inside_dd;
            fallback_d<=fallback;fallback_dd<=fallback_d;fallback_ddd<=fallback_dd;
            pixel_data<=inside_ddd ? (frame_valid ? corrected : fallback_ddd) : 16'd0;
        end
    end
endmodule
