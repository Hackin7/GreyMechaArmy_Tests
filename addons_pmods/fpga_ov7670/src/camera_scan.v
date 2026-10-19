// Probe write addresses only after initialization has failed. No register data
// is written. Each probe ends with STOP; scan is repeated only after reset.
module camera_scan #(parameter integer QUARTER_CYCLES=1250)(
    input wire clk, resetn, enable, sda_in,
    output wire scl_low, sda_low,
    output reg complete,
    output reg [6:0] address, first_ack,
    output reg [7:0] ack_count
);
    reg launch, waiting;
    wire done, nack, busy;
    wire [7:0] unused_data;
    sccb_byte #(.QUARTER_CYCLES(QUARTER_CYCLES)) probe(
        .clk(clk),.resetn(resetn),.start(launch),.send_start(1'b1),
        .send_stop(1'b1),.read_byte(1'b0),.tx_data({address,1'b0}),
        .sda_in(sda_in),.scl_low(scl_low),.sda_low(sda_low),
        .busy(busy),.done(done),.nack(nack),.rx_data(unused_data));
    always @(posedge clk) begin
        launch<=0;
        if(!resetn) begin
            complete<=0; address<=7'h08; first_ack<=0; ack_count<=0; waiting<=0;
        end else if(enable && !complete) begin
            if(!waiting) begin launch<=1; waiting<=1; end
            else if(done) begin
                if(!nack) begin
                    if(ack_count==0) first_ack<=address;
                    ack_count<=ack_count+1'b1;
                end
                if(address==7'h77) complete<=1;
                else begin address<=address+1'b1; waiting<=0; end
            end
        end
    end
endmodule
