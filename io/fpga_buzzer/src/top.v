module top(
    output buzzer
);
    wire clk_int;
    defparam OSCI1.DIV = "5";
    OSCG OSCI1 (.OSC(clk_int));

    localparam integer CLK_HZ = 62_000_000;
    localparam integer NOTE_HZ = 440;
    localparam integer HALF_PERIOD_CLKS = (CLK_HZ + NOTE_HZ) / (2 * NOTE_HZ);

    reg [31:0] counter = 0;
    reg buzzer_reg = 1'b0;

    always @(posedge clk_int) begin
        if (counter == HALF_PERIOD_CLKS - 1) begin
            counter <= 0;
            buzzer_reg <= ~buzzer_reg;
        end else begin
            counter <= counter + 1;
        end
    end

    assign buzzer = buzzer_reg;
endmodule
