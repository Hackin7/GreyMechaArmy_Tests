`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.03.2024 18:23:54
// Design Name: 
// Module Name: middle_square_timer
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module middle_square_timer
    #(parameter  // Greybadge port: clk = 12.9 MHz (1 s = 12_900_000 cycles)
        COUNT_BUTTON   = 645_000,   // 50 ms  (was 5_000_000  @ 100 MHz)
        COUNT_DEBOUNCE = 2_580_000, // 200 ms (was 20_000_000 @ 100 MHz)
        BITWIDTH=32,
        MAX_STATE=3,
        LOOP_STATE=1
        )
    (
        input clk, input reset, input btn, 
        output reg [2:0] trigger_state = 0, // The main state output
        output [BITWIDTH-1:0] debug_counter
    );
    /* 
    Trigger state goes to
    0 -> 1 -> ..... -> MAX_STATE
         |                   |
     LOOP_STATE (0 to MAX)   |
         ^                   |
         |--------------------
    */ 
    
    assign debug_counter = counter;
    
    reg [BITWIDTH-1:0] counter = 0;
    reg counter_overflow = 0; 
    reg state = 0; // 0 for check, 1 for debounce
    
    reg prev_button_state = 0; 
    wire button_release_valid = 1;// Don't need keep track timing //(counter < COUNT_BUTTON) && (counter_overflow == 0);
    
    always @ (posedge clk) begin
        if (state == 0) begin 
            /* 4 states
                - stay low
                - rise
                - stay high - Pressed
                - fall      - Released -> Go to debounce state
            */
            // Not pressed - Don't do anything
            
            // Overflow trigger ///////////////////////////////
            if (counter > COUNT_BUTTON) begin
                counter_overflow <= 1;
            end
            // Pressed - count time passed /////////////////////
            if (prev_button_state == 1 && btn == 1) begin 
                counter <= counter + 1;     
            // Released ////////////////////////////////////////
            end else if (prev_button_state == 1 && btn == 0 && button_release_valid) begin 
                // switch modes
                if (trigger_state == MAX_STATE) begin
                    trigger_state <= LOOP_STATE;
                end else begin
                    trigger_state <= trigger_state + 1;
                end
                // Reset
                counter <= 0;
                counter_overflow <= 0;
                state <= 1; // Switch to debounce state
            end
        end else begin // Debounce
            counter <= counter + 1;
            if (counter == COUNT_DEBOUNCE) begin
                counter <= 0;
                state <= 0;
            end
        end
        if (reset) begin
            trigger_state <= 0; // Nothing show up
            state <= 0;
            counter <= 0;
            counter_overflow <= 0;
        end
        
        prev_button_state <= btn;
    end
endmodule

