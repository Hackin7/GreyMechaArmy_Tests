// W25Q128JV 1-1-4 quad-output reads. No QPI/continuous-read mode.
// QE is set with volatile 50h/31h, preserving all other SR2 bits.
// Two or four clk cycles per SCK; IO0 releases before the final dummy falling edge.
module gba_qspi_reader #(parameter CLOCK_CYCLES=4, RX_REGISTER=0)(
    input wire clk,reset,start, input wire [22:0] line_address,
    input wire fill_ready, input wire [3:0] dq,
    output reg busy,ready,fault,
    output reg fill_we, output reg [7:0] fill_offset,fill_data,
    output reg flash_clk,flash_cs_n,flash_mosi,output wire mosi_oe
);
    localparam GAP=0,IDLE=1,SEND=2,READ=3,FINISH=4,FAILED=5,BYTE_GAP=6;
    reg [2:0] state,init_step;
    reg [3:0] phase;
    reg [6:0] gap;
    reg gap_done;
    reg [39:0] tx;
    reg [5:0] left;
    reg [7:0] sr2,sampled,offset;
    reg high_nibble;
    reg [3:0] nibble;
    wire [4:0] cycles=ready?CLOCK_CYCLES:16;
    wire [3:0] fall=ready?(CLOCK_CYCLES==2?1:2):8;
    // Unconditional input registers allow nextpnr to pack the quad data FFs into I/O cells.
    (* syn_useioff=1 *) reg [3:0] dq_registered;
    reg capture_high,capture_low;
    reg [7:0] capture_offset;
    always @(posedge clk)dq_registered<=dq;
    wire [7:0] last_status=sampled;
    assign mosi_oe=state==SEND && !(ready && left<=8);
    always @(posedge clk)begin
        fill_we<=0;
        capture_high<=state==READ && phase==1 && high_nibble;
        capture_low<=state==READ && phase==1 && !high_nibble;
        capture_offset<=offset;
        if(RX_REGISTER)begin
            if(capture_high)nibble<=dq_registered;
            if(capture_low)begin
                fill_data<={nibble,dq_registered};fill_offset<=capture_offset;fill_we<=1;
            end
        end
        gap_done<=gap==1;
        if(reset)begin
            capture_high<=0;capture_low<=0;capture_offset<=0;gap_done<=0;state<=GAP;init_step<=0;phase<=0;gap<=64;tx<=0;left<=0;
            sr2<=0;sampled<=0;offset<=0;high_nibble<=1;nibble<=0;
            busy<=1;ready<=0;fault<=0;flash_clk<=0;flash_cs_n<=1;
            flash_mosi<=0;fill_offset<=0;fill_data<=0;
        end else case(state)
            GAP: if(!gap_done)gap<=gap-1'b1;else if(init_step==4)begin
                state<=IDLE;busy<=0;ready<=1;
            end else begin
                state<=SEND;phase<=0;sampled<=0;flash_cs_n<=0;
                case(init_step)
                    0,3:begin tx<={8'h35,32'd0};left<=16;flash_mosi<=0;end
                    1:begin tx<={8'h50,32'd0};left<=8;flash_mosi<=0;end
                    2:begin tx<={8'h31,(sr2|8'h02),24'd0};left<=16;flash_mosi<=0;end
                    default:state<=FAILED;
                endcase
            end
            IDLE: if(start)begin
                tx<={8'h6b,(24'h100000+{1'b0,line_address[22:8],8'd0}),8'd0};
                left<=40;phase<=0;offset<=0;high_nibble<=1;
                flash_mosi<=0;flash_cs_n<=0;busy<=1;state<=SEND;
            end
            SEND:begin
                phase<=phase==cycles-1?0:phase+1'b1;
                if(phase==0)flash_clk<=1;
                if(phase==1&&(init_step==0||init_step==3)&&left<=8)
                    sampled<={sampled[6:0],(RX_REGISTER?dq_registered[1]:dq[1])};
                if(phase==fall)begin flash_clk<=0;tx<={tx[38:0],1'b0};flash_mosi<=tx[38];end
                if(phase==cycles-1)begin
                    if(left!=1)left<=left-1'b1;
                    else if(init_step==4)state<=READ;
                    else begin
                        flash_cs_n<=1;gap<=64;state<=GAP;
                        case(init_step)
                            0:begin sr2<=last_status;init_step<=last_status[1]?4:1;end
                            1:init_step<=2;
                            2:init_step<=3;
                            3:if(last_status[1])init_step<=4;else begin fault<=1;state<=FAILED;end
                        endcase
                    end
                end
            end
            READ:begin
                if(phase==0)begin
                    if(!high_nibble||fill_ready)begin flash_clk<=1;phase<=1;end
                end else begin
                    phase<=phase==cycles-1?0:phase+1'b1;
                    if(phase==1 && !RX_REGISTER)begin
                        if(high_nibble)nibble<=dq;
                        else begin fill_data<={nibble,dq};fill_offset<=offset;fill_we<=1;end
                    end
                    if(phase==fall)flash_clk<=0;
                    if(phase==cycles-1)begin
                        high_nibble<=!high_nibble;
                        if(!high_nibble)begin
                            if(offset==255)state<=FINISH;else begin
                                offset<=offset+1'b1;
                                if(CLOCK_CYCLES==2)state<=BYTE_GAP;
                            end
                        end
                    end
                end
            end
            BYTE_GAP:if(!RX_REGISTER||fill_we)state<=READ; // Let the FIFO accept fill_we before testing full.
            FINISH:begin flash_cs_n<=1;gap<=8;state<=GAP;end
            FAILED:begin flash_cs_n<=1;flash_clk<=0;busy<=1;end
            default:begin fault<=1;state<=FAILED;end
        endcase
    end
endmodule
