// Independent reference: four separate ARM shifters, including nonzero
// multiples of 32 for ROR (value unchanged, bit 31 in the carry flag).
module cpu_shifter_proof(input [31:0] value, input [7:0] amount,
                        input [1:0] mode, input rrx,carry_in, output matches);
    wire [31:0] result;
    wire carry_out;
    gba_alu_shifter dut(.*);
    reg [31:0] reference;
    reg reference_carry;
    always @* begin
        reference=value;
        reference_carry=carry_in;
        case(mode)
            0: if(amount>=32) begin
                reference=0; reference_carry=amount==32 ? value[0] : 0;
            end else if(amount>0) begin
                reference=value<<amount; reference_carry=value[32-amount];
            end
            1: if(amount>=32) begin
                reference=0; reference_carry=amount==32 ? value[31] : 0;
            end else if(amount>0) begin
                reference=value>>amount; reference_carry=value[amount-1];
            end
            2: if(amount>=32) begin
                reference={32{value[31]}}; reference_carry=value[31];
            end else if(amount>0) begin
                reference=$signed(value)>>>amount; reference_carry=value[amount-1];
            end
            3: if(amount>0) begin
                if(amount[4:0]==0) reference_carry=value[31];
                else begin
                    reference=(value>>amount[4:0])|(value<<(32-amount[4:0]));
                    reference_carry=value[amount[4:0]-1];
                end
            end
        endcase
        if(rrx) begin reference={carry_in,value[31:1]}; reference_carry=value[0]; end
    end
    assign matches=result==reference && carry_out==reference_carry;
endmodule
