// The reference uses the upstream CPU's separate arithmetic and borrow tests.
module cpu_arithmetic_proof(input [31:0] a,b,input subtract,with_carry,carry_in,
                           output matches);
    wire [32:0] shared_result;
    gba_alu_addsub dut(.a(a),.b(b),.subtract(subtract),.with_carry(with_carry),
                      .carry_in(carry_in),.result(shared_result));
    reg [32:0] reference;
    always @* begin
        if(!subtract) reference={1'b0,a}+{1'b0,b}+(with_carry&&carry_in);
        else begin
            reference[31:0]=a-b-(with_carry&&!carry_in);
            reference[32]=(!with_carry||carry_in) ? a>=b : (a!=0&&(a-32'd1)>=b);
        end
    end
    assign matches=shared_result==reference;
endmodule
