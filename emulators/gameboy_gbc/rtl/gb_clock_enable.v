module gb_clock_enable (
    input  wire clk,
    input  wire reset,
    input  wire enable,
    output reg  ce,
    output reg  ce_n,
    output reg  ce_2x
);
    // The alternating ce/ce_n pulses together form the 8.388608 MHz enable
    // stream required for the original 4.194304 MHz Game Boy clock.  At the
    // Army's proven 15 MHz PLL clock, 15 MHz * 32768 / 58594 = 8.388572 MHz
    // (4.3 ppm low).
    reg [16:0] phase;
    reg        half_phase;
    reg        ce_2x_guard;
    reg [17:0] sum;

    always @(posedge clk) begin
        ce    <= 1'b0;
        ce_n  <= 1'b0;
        ce_2x <= 1'b0;

        if (reset) begin
            phase      <= 17'd0;
            half_phase <= 1'b0;
            ce_2x_guard <= 1'b0;
        end else if (enable) begin
            ce_2x_guard <= 1'b0;
            sum = {1'b0, phase} + 18'd32768;
            if (sum >= 18'd58594) begin
                phase <= sum - 18'd58594;
                // clk_core is only 15 MHz. The 8.39 MHz NCO occasionally
                // produces adjacent events, but the synchronous CPU RAMs
                // require one intervening FPGA clock for read data. Keep the
                // PPU's ce/ce_n cadence exact and cap only double-speed CPU
                // enables so they can never occur on consecutive clocks.
                if (!ce_2x_guard) begin
                    ce_2x <= 1'b1;
                    ce_2x_guard <= 1'b1;
                end
                if (half_phase)
                    ce_n <= 1'b1;
                else
                    ce <= 1'b1;
                half_phase <= ~half_phase;
            end else begin
                phase <= sum[16:0];
            end
        end else ce_2x_guard <= 1'b0;
    end
endmodule
