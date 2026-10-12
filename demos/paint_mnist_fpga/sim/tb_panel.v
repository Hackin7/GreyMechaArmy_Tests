`timescale 1ns/1ps
module tb_panel;
    reg clk=0; always #5 clk=~clk;
    reg resetn=0,enable=0;
    wire [15:0] pixel_index,pixel_data;
    wire [9:0] address;
    reg [2:0] canvas [0:783];
    reg [6:0] cursor_x=28;
    reg [5:0] cursor_y=28;
    reg [2:0] selected=3;
    reg [3:0] prediction=0;
    reg valid=1,updating=0;
    wire scl,mosi,cs,dc,frame_done;
    wire [15:0] bgr={pixel_data[4:0],pixel_data[10:5],pixel_data[15:11]};
    paint_renderer renderer(.clk(clk),.resetn(resetn),.pixel_index(pixel_index),
        .canvas_address(address),.canvas_colour(canvas[address]),
        .cursor_x(cursor_x),.cursor_y(cursor_y),.chosen_colour(selected),
        .prediction(prediction),.prediction_valid(valid),.updating(updating),.pixel_data(pixel_data));
    oled_stream stream(.clk(clk),.resetn(resetn),.enable(enable),.pixel_index(pixel_index),
        .pixel_data(bgr),.sclk(scl),.mosi(mosi),.cs(cs),.dc(dc),.frame_done(frame_done));
    reg image [0:4703];
    reg [15:0] shift=0;
    reg [15:0] decoded;
    integer bit_count=0, pixels=0, f,case_no,j;
    always @(posedge scl) if(!cs && dc) begin
        shift={shift[14:0],mosi};
        if(bit_count==15) begin
            decoded={shift[4:0],shift[10:5],shift[15:11]};
            $fdisplay(f,"%04x",decoded);
            pixels=pixels+1; bit_count=0;
        end else bit_count=bit_count+1;
    end
    initial begin
        $readmemh("build/generated/images.mem",image);
        repeat(5) @(negedge clk); resetn=1;
        for(case_no=0;case_no<3;case_no=case_no+1) begin
            for(j=0;j<784;j=j+1) begin
                if(case_no==0) canvas[j]=image[j] ? 3 : 0;
                else if(case_no==1) canvas[j]=0;
                else canvas[j]=((j%28)/7)+1;
            end
            valid=(case_no!=1); prediction=(case_no==2)?7:0; updating=(case_no==2);
            selected=(case_no==2)?2:3;
            cursor_x=(case_no==2)?70:28; cursor_y=(case_no==2)?40:28;
            case(case_no)
                0:f=$fopen("build/frame0.rgb","w");
                1:f=$fopen("build/frame1.rgb","w");
                2:f=$fopen("build/frame2.rgb","w");
            endcase
            pixels=0; bit_count=0; shift=0;
            repeat(5) @(negedge clk); enable=1;
            wait(frame_done); @(negedge clk); enable=0;
            if(pixels!=57600 || bit_count!=0) $fatal(1,"Bad SPI frame size=%0d",pixels);
            $fclose(f);
            $display("PASS panel frame=%0d pixels=%0d physical BGR decoded",case_no,pixels);
            repeat(5) @(negedge clk);
        end
        $finish;
    end
    initial begin #65000000; $fatal(1,"Panel timeout"); end
endmodule
