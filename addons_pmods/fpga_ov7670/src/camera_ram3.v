// Three 19200-word images: 19 + 19 + 18 DP16KD (1024x16) blocks.
// Bank 2's last 768 words use distributed dual-clock memory.
module camera_ram3(
    input wire pclk,write_enable,
    input wire [1:0] write_bank,read_bank,
    input wire [14:0] write_address,read_address,
    input wire [15:0] write_data,
    input wire clk,
    output reg [15:0] read_data
);
    wire [15:0] q[0:56];
    wire [15:0] q0[0:18],q1[0:18],q2[0:18];
    genvar b,c;
    generate for(b=0;b<3;b=b+1) begin: banks
        for(c=0;c<19;c=c+1) begin: chunks
            if(b==2 && c==18) begin: tail
                (* ram_style="distributed" *) reg [15:0] mem[0:767];
                reg [15:0] qr;
                always @(posedge pclk)
                    if(write_enable && write_bank==b && write_address[14:10]==c && write_address[9:0]<768)
                        mem[write_address[9:0]]<=write_data;
                always @(posedge clk) qr<=mem[read_address[9:0]];
                assign q[b*19+c]=qr;
            end else begin: bram
                (* ram_style="block" *) reg [15:0] mem[0:1023];
                reg [15:0] qr;
                always @(posedge pclk)
                    if(write_enable && write_bank==b && write_address[14:10]==c)
                        mem[write_address[9:0]]<=write_data;
                always @(posedge clk) qr<=mem[read_address[9:0]];
                assign q[b*19+c]=qr;
            end
        end
    end
    for(c=0;c<19;c=c+1) begin: bank_mux_inputs
        assign q0[c]=q[c];assign q1[c]=q[19+c];assign q2[c]=q[38+c];
    end endgenerate
    reg [4:0] chunk;
    reg [15:0] bank0,bank1,bank2;
    always @(posedge clk) begin
        chunk<=read_address[14:10];
        bank0<=q0[chunk];bank1<=q1[chunk];bank2<=q2[chunk];
        read_data<=read_bank==0 ? bank0 : read_bank==1 ? bank1 : bank2;
    end
endmodule
