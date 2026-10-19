// SCCB byte engine. SDA uses open drain; top actively drives SIOC from
// scl_low because OV7670 SCCB does not stretch this single-master clock.
module sccb_byte #(
    parameter integer QUARTER_CYCLES=188
)(
    input wire clk, resetn, start,
    input wire send_start, send_stop, read_byte,
    input wire [7:0] tx_data,
    input wire sda_in,
    output reg scl_low, sda_low,
    output reg busy, done, nack,
    output reg [7:0] rx_data
);
    localparam IDLE=0, START_A=1, START_B=2, BIT_LOW=3,
        BIT_HIGH=4, BIT_SAMPLE=5, BIT_FALL=6, ACK_LOW=7,
        ACK_HIGH=8, ACK_SAMPLE=9, ACK_FALL=10,
        STOP_A=11, STOP_B=12, STOP_C=13, FINISH=14;
    reg [3:0] state;
    reg [2:0] bit_index;
    reg [7:0] tx;
    reg reading, stopping;
    reg [$clog2(QUARTER_CYCLES+1)-1:0] timer;
    (* async_reg = "true" *) reg [1:0] sda_sync;
    always @(posedge clk) begin
        if (!resetn) begin
            state<=IDLE; timer<=0; bit_index<=7; tx<=0;
            reading<=0; stopping<=0; scl_low<=0; sda_low<=0;
            busy<=0; done<=0; nack<=0; rx_data<=0; sda_sync<=3;
        end else begin
            sda_sync<={sda_sync[0],sda_in}; done<=0;
            if (state==IDLE) begin
                if (start) begin
                    busy<=1; nack<=0; rx_data<=0; tx<=tx_data;
                    reading<=read_byte; stopping<=send_stop;
                    bit_index<=7; timer<=0;
                    state<=send_start ? START_A : BIT_LOW;
                end
            end else if (timer != QUARTER_CYCLES-1) timer<=timer+1'b1;
            else begin
                timer<=0;
                case (state)
                    START_A: begin scl_low<=0; sda_low<=0; state<=START_B; end
                    START_B: begin sda_low<=1; state<=BIT_LOW; end
                    BIT_LOW: begin
                        scl_low<=1; sda_low<=!reading && !tx[bit_index]; state<=BIT_HIGH;
                    end
                    BIT_HIGH: begin scl_low<=0; state<=BIT_SAMPLE; end
                    BIT_SAMPLE: begin
                        if (reading) rx_data[bit_index]<=sda_sync[1];
                        state<=BIT_FALL;
                    end
                    BIT_FALL: begin
                        scl_low<=1;
                        if (bit_index==0) state<=ACK_LOW;
                        else begin bit_index<=bit_index-1'b1; state<=BIT_LOW; end
                    end
                    ACK_LOW: begin sda_low<=0; state<=ACK_HIGH; end // master NACK on reads
                    ACK_HIGH: begin scl_low<=0; state<=ACK_SAMPLE; end
                    ACK_SAMPLE: begin
                        if (!reading) nack<=sda_sync[1];
                        state<=ACK_FALL;
                    end
                    ACK_FALL: begin scl_low<=1; state<=stopping ? STOP_A : FINISH; end
                    STOP_A: begin sda_low<=1; state<=STOP_B; end
                    STOP_B: begin scl_low<=0; state<=STOP_C; end
                    STOP_C: begin sda_low<=0; state<=FINISH; end
                    FINISH: begin busy<=0; done<=1; state<=IDLE; end
                    default: state<=IDLE;
                endcase
            end
        end
    end
endmodule
