`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
//
//  FILL IN THE FOLLOWING INFORMATION:
//  STUDENT A NAME: 
//  STUDENT B NAME:
//  STUDENT C NAME: 
//  STUDENT D NAME:  
//
//////////////////////////////////////////////////////////////////////////////////


// Greybadge port: dropped Oled_Display and MouseCtl (Vivado-only IP).
// OLED is driven externally by oled_gc9a01; pixel_index in, pixel_data out.
// PMOD JB pins removed. Mouse signals stubbed to safe defaults (centered,
// no clicks/events) so mouse-using tasks still compile.
module Top_Student (
    // Control
    input clk,
    // LEDs, Switches, Buttons
    input btnC, btnU, btnL, btnR, btnD, input [15:0] sw, output [15:0] led,
    // 7 Segment Display
    output [6:0] seg, output dp, output [3:0] an,
    // OLED interface (driven by external oled_gc9a01)
    input  [12:0] oled_pixel_index,
    output [15:0] oled_pixel_data
);

    //// Setup ///////////////////////////////////////////////////////////////////////////////////////////////////////
    //// Clocks /////////////////////////////////////////////
    wire clk_25mhz, clk_12_5mhz, clk_6_25mhz, slow_clk;
    
    assign clk25m = clk;
    clk_counter #(1, 1, 32) clk12p5m (clk, clk_12_5mhz);
    clk_counter #(2, 2, 32) clk6p25m (clk, clk_6_25mhz);
    clk_counter #(19400000, 19400000, 32) clkslow (clk, slow_clk); // 1hz

    /*clk_counter #(2, 2, 32) clk25m (clk, clk_25mhz);
    clk_counter #(4, 4, 32) clk12p5m (clk, clk_12_5mhz);
    clk_counter #(8, 8, 32) clk6p25m (clk, clk_6_25mhz);
    clk_counter #(50_000_000, 50_000_000, 32) clkslow (clk, slow_clk); // 1hz
    */

    //// Mouse stubs (no PS/2 mouse on greybadge) ////////////
    wire [11:0] mouse_xpos         = 12'd40;
    wire [11:0] mouse_ypos         = 12'd24;
    wire [3:0]  mouse_zpos         = 4'd0;
    wire        mouse_left_click   = 1'b0;
    wire        mouse_middle_click = 1'b0;
    wire        mouse_right_click  = 1'b0;
    wire        mouse_new_event    = 1'b0;
    

    //// Group Task — STUBBED OUT for greybadge port. //////////////////////////
    // The original adaptor_task_group depends on given_paint/module_pack which
    // instantiates Vivado's blk_mem_gen_* IP cores. Those aren't available in
    // the open-source toolchain. Group output is hardcoded to defaults; sw[4]
    // still selects this "task" but it just shows a black screen.
    wire group_reset;
    wire [15:0] group_led            = 16'b0;
    wire [6:0]  group_seg            = 7'b1111111;
    wire        group_dp             = 1'b1;
    wire [3:0]  group_an             = 4'b1111;
    wire [15:0] group_oled_pixel_data = 16'h0000;

    //// Task A //////////////////////////////////////////////////////////////////////////////////////////////////
    wire a_reset;
    wire [15:0] a_led; 
    wire [6:0] a_seg; 
    wire a_dp;
    wire [3:0] a_an;
    wire [15:0] a_oled_pixel_data;

    adaptor_task_a task_a(
        .reset(a_reset), .clk(clk),
        .btnC(btnC), .btnU(btnU), .btnL(btnL), .btnR(btnR), .btnD(btnD), .sw(sw), .led(a_led), 
        .seg(a_seg), .dp(a_dp), .an(a_an),
        .oled_pixel_index(oled_pixel_index), .oled_pixel_data(a_oled_pixel_data),
        .mouse_xpos(mouse_xpos), .mouse_ypos(mouse_ypos), .mouse_zpos(mouse_zpos),
        .mouse_left_click(mouse_left_click), .mouse_middle_click(mouse_middle_click),
        .mouse_right_click(mouse_right_click), .mouse_new_event(mouse_new_event)
    );
    
    //// Task B //////////////////////////////////////////////////////////////////////////////////////////////////
    wire b_reset;
    wire [15:0] b_oled_pixel_data;
    
    adaptor_task_b task_b(
    .clk(clk), .reset(b_reset), .btnC(btnC), .btnL(btnL), .btnR(btnR),
    .sw(sw), .oled_pixel_index(oled_pixel_index), .oled_pixel_data(b_oled_pixel_data)
    );

    //// Task C //////////////////////////////////////////////////////////////////////////////////////////////////
    wire c_reset;
    wire [15:0] c_led; 
    wire [6:0] c_seg; 
    wire c_dp;
    wire [3:0] c_an;
    wire [15:0] c_oled_pixel_data;

    adaptor_task_c task_c(
        .reset(c_reset), .clk(clk),
        .btnC(btnC), .btnU(btnU), .btnL(btnL), .btnR(btnR), .btnD(btnD), .sw(sw), .led(c_led), 
        .seg(c_seg), .dp(c_dp), .an(c_an),
        .oled_pixel_index(oled_pixel_index), .oled_pixel_data(c_oled_pixel_data)/*,
        .mouse_xpos(mouse_xpos), .mouse_ypos(mouse_ypos), .mouse_zpos(mouse_zpos),
        .mouse_left_click(mouse_left_click), .mouse_middle_click(mouse_middle_click),
        .mouse_right_click(mouse_right_click), .mouse_new_event(mouse_new_event)*/
    );
    //// Task D //////////////////////////////////////////////////////////////////////////////////////////////////
        wire d_reset;
        wire [15:0] d_led; 
        wire [6:0] d_seg; 
        wire d_dp;
        wire [3:0] d_an;
        wire [15:0] d_oled_pixel_data;
    
        adaptor_task_d task_d(
            .reset(d_reset), .clk(clk),
            .btnC(btnC), .btnU(btnU), .btnL(btnL), .btnR(btnR), .btnD(btnD), .sw(sw), .led(c_led), 
            .seg(d_seg), .dp(d_dp), .an(d_an),
            .oled_pixel_index(oled_pixel_index), .oled_pixel_data(d_oled_pixel_data)/*,
            .mouse_xpos(mouse_xpos), .mouse_ypos(mouse_ypos), .mouse_zpos(mouse_zpos),
            .mouse_left_click(mouse_left_click), .mouse_middle_click(mouse_middle_click),
            .mouse_right_click(mouse_right_click), .mouse_new_event(mouse_new_event)*/
        );
    //// Overall Control Logic ////////////////////////////////////////////////////////////////////////////////////
    // 4.E1
    wire enable_task_group = sw[4];
    wire enable_task_a = sw[0] & ~(sw[1] | sw[2] | sw[3] | sw[4]);
    wire enable_task_b = sw[1] & ~(sw[2] | sw[3] | sw[4]);
    wire enable_task_c = sw[2] & ~(sw[3] | sw[4]);
    wire enable_task_d = sw[3] & ~(sw[4]);
    wire [15:0] indiv_led;

    assign led = enable_task_group ? group_led : indiv_led;
    assign seg = enable_task_group ? group_seg : 7'b1111111;
    assign dp = enable_task_group ? group_dp : 1;
    assign an = enable_task_group ? group_an : 4'b1111;
    assign oled_pixel_data = enable_task_group ? group_oled_pixel_data : (
        enable_task_d ? d_oled_pixel_data : (
        enable_task_c ? c_oled_pixel_data : (
        enable_task_b ? b_oled_pixel_data : (
        enable_task_a ? a_oled_pixel_data :
         16'hFFFF
        )))
    );
    // 4.E2
    assign indiv_led = {12'b0, enable_task_d, enable_task_c, enable_task_b, enable_task_a}; 

    // 4.E3                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         
    assign group_reset = ~enable_task_group;
    assign mouse_reset = group_reset;
    assign a_reset = ~enable_task_a; // | (enable_task_b | enable_task_c | enable_task_d | enable_task_group);
    assign b_reset = ~enable_task_b; // | (enable_task_c | enable_task_d | enable_task_group);
    assign c_reset = ~enable_task_c; // | (enable_task_d | enable_task_group);
    assign d_reset = ~enable_task_d; // | (enable_task_group);

endmodule
