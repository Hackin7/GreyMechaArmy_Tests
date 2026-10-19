// Register read: 42,subaddress,STOP; START,43,read,NACK,STOP.
module sccb_register #(
    parameter integer QUARTER_CYCLES=188
)(
    input wire clk, resetn, start, read_register,
    input wire [7:0] address, value,
    input wire sda_in,
    output wire scl_low, sda_low,
    output reg busy, done, error,
    output reg [7:0] result,
    output reg [3:0] nack_mask
);
    reg launch;
    reg [2:0] byte_number;
    reg reading, waiting;
    reg [7:0] subaddress, data_value;
    wire byte_done, byte_nack, byte_busy;
    wire [7:0] received;
    wire receiving = reading && byte_number==3;
    wire starting = byte_number==0 || (reading && byte_number==2);
    wire stopping = reading ? byte_number==1 || byte_number==3 : byte_number==2;
    wire [7:0] transmitted = byte_number==0 ? 8'h42 :
        byte_number==1 ? subaddress : reading ? 8'h43 : data_value;
    sccb_byte #(.QUARTER_CYCLES(QUARTER_CYCLES)) engine(
        .clk(clk),.resetn(resetn),.start(launch),.send_start(starting),
        .send_stop(stopping),.read_byte(receiving),.tx_data(transmitted),
        .sda_in(sda_in),.scl_low(scl_low),.sda_low(sda_low),
        .busy(byte_busy),.done(byte_done),.nack(byte_nack),.rx_data(received));
    always @(posedge clk) begin
        launch<=0; done<=0;
        if (!resetn) begin
            busy<=0; error<=0; result<=0; byte_number<=0; nack_mask<=0;
            reading<=0; waiting<=0; subaddress<=0; data_value<=0;
        end else if (!busy) begin
            if (start) begin
                busy<=1; error<=0; byte_number<=0; reading<=read_register; nack_mask<=0;
                subaddress<=address; data_value<=value; waiting<=0;
            end
        end else if (!waiting) begin
            launch<=1; waiting<=1;
        end else if (byte_done) begin
            if (!receiving && byte_nack) begin error<=1; nack_mask[byte_number]<=1; end
            // Complete transaction even after NACK, so the bus gets STOP.
            if ((!reading && byte_number==2) || receiving) begin
                result<=received; busy<=0; done<=1;
            end else begin byte_number<=byte_number+1'b1; waiting<=0; end
        end
    end
endmodule
