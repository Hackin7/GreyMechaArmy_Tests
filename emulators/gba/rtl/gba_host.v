// Existing GB CRC16 framing, version 1. Mutations finish atomically after CRC.
// STATUS (20) is available while a memory operation is busy. DATA (21) returns
// the completed read buffer separately so status polling cannot destroy it.
module gba_host(
    input wire clk,reset,input wire [7:0] rx_data,input wire rx_valid,
    output reg [7:0] tx_data,output reg tx_valid,input wire tx_ready,
    output reg run,pause,output reg reset_pulse,
    output reg [24:0] max_rom_addr,output reg flash_1m,
    output reg inject_enable,output reg [9:0] injected,
    input wire ram_ready,ram_idle,ram_fault,panel_ready,overflow,
    input wire [23:0] device_id,input wire [31:0] pc,frames,flash_misses,
    input wire [6:0] physical,input wire [9:0] keys,
    output reg mem_req,mem_read,output reg [22:0] mem_addr,
    output reg [31:0] mem_wdata,output reg [3:0] mem_be,
    input wire mem_done,input wire [31:0] mem_rdata,
    output wire busy,output reg [7:0] error,last_sequence
);
    reg [3:0] state,exec_state;
    reg [7:0] opcode,seq,crc_low,active_op,active_seq;
    reg [31:0] address;
    reg [22:0] exec_address;
    // A validated fill can cover all 8 MiB, including the 0x800000 count.
    reg [23:0] remaining;
    reg [23:0] packet_timeout;
    reg [8:0] length,count,index,read_length,response_length,response_index;
    reg [15:0] crc;
    reg [7:0] params[0:4],status_buffer[0:31];
    wire [31:0] payload_word;
    // Keep word zero prefetched while receiving a packet. On completion of
    // each PSRAM word, fetch the next word for the following issue cycle.
    wire [5:0] payload_read_index=exec_state==0 ? 6'd0 :
        index[7:2]+((exec_state==2 && mem_done) ? 6'd1 : 6'd0);
    genvar payload_lane;
    generate for(payload_lane=0;payload_lane<4;payload_lane=payload_lane+1) begin: payload_bytes
        (* ram_style="block" *) reg [7:0] bank[0:63];
        reg [7:0] selected;
        always @(posedge clk) begin
            if(!reset && rx_valid && state==10 && !busy && count[1:0]==payload_lane)
                bank[count[7:2]]<=rx_data;
            selected<=bank[payload_read_index];
        end
        assign payload_word[payload_lane*8 +: 8]=selected;
    end endgenerate
    reg [31:0] read_buffer[0:63];
    integer lane;
    reg response_data;
    assign busy=exec_state!=0;
    function [15:0] crc_byte;
        input [15:0] old;input [7:0] val;integer i;reg [15:0] c;
        begin c=old^{val,8'd0};for(i=0;i<8;i=i+1)c=c[15] ? {c[14:0],1'b0}^16'h1021:{c[14:0],1'b0};crc_byte=c;end
    endfunction
    task status_response;
        begin
            status_buffer[0]<=8'h47;status_buffer[1]<=1;status_buffer[2]<=last_sequence;
            status_buffer[3]<={overflow,ram_fault,panel_ready,ram_idle,ram_ready,pause,run,busy};
            status_buffer[4]<=pc[7:0];status_buffer[5]<=pc[15:8];status_buffer[6]<=pc[23:16];status_buffer[7]<=pc[31:24];
            status_buffer[8]<=device_id[7:0];status_buffer[9]<=device_id[15:8];status_buffer[10]<=device_id[23:16];status_buffer[11]<=error;
            status_buffer[12]<=keys[7:0];status_buffer[13]<={6'd0,keys[9:8]};status_buffer[14]<={1'b0,physical};status_buffer[15]<=0;
            status_buffer[16]<=frames[7:0];status_buffer[17]<=frames[15:8];status_buffer[18]<=frames[23:16];status_buffer[19]<=frames[31:24];
            status_buffer[20]<=flash_misses[7:0];status_buffer[21]<=flash_misses[15:8];status_buffer[22]<=flash_misses[23:16];status_buffer[23]<=flash_misses[31:24];
            status_buffer[24]<=0;status_buffer[25]<=0;status_buffer[26]<=0;status_buffer[27]<=0;
            status_buffer[28]<=0;status_buffer[29]<=0;status_buffer[30]<=0;status_buffer[31]<=0;
            response_data<=0;response_length<=32;response_index<=0;
        end
    endtask
    always @(posedge clk) begin
        mem_req<=0;reset_pulse<=0;
        if(reset) begin
            state<=0;exec_state<=0;crc<=16'hffff;count<=0;length<=0;packet_timeout<=0;
            run<=0;pause<=1;inject_enable<=0;injected<=0;max_rom_addr<=0;flash_1m<=0;
            tx_valid<=0;response_length<=0;response_index<=0;error<=0;last_sequence<=0;
            read_length<=0;index<=0;mem_be<=0;mem_addr<=0;mem_read<=1;mem_wdata<=0;
        end else begin
            if(rx_valid||state==0) packet_timeout<=0;
            else if(&packet_timeout) begin state<=0;error<=8;packet_timeout<=0;end
            else packet_timeout<=packet_timeout+1'b1;
            if(tx_valid&&tx_ready) begin tx_valid<=0;response_index<=response_index+1'b1;end
            if(!tx_valid&&response_index<response_length) begin
                tx_data<=response_data ? read_buffer[response_index[7:2]][response_index[1:0]*8 +: 8]:status_buffer[response_index[4:0]];tx_valid<=1;
            end
            case(exec_state)
                1: begin
                    mem_addr<=exec_address[22:0];mem_be<=4'hf;
                    mem_read<=active_op==8'h12||active_op==8'h15;
                    if(active_op==8'h10) mem_wdata<=payload_word;
                    else mem_wdata<={4{params[4]}};
                    mem_req<=1;exec_state<=2;
                end
                2: if(mem_done) begin
                    for(lane=0;lane<4;lane=lane+1) begin
                        if(active_op==8'h12 || (active_op==8'h15 && index[1:0]==lane))
                            read_buffer[index[7:2]][lane*8 +: 8]<=active_op==8'h12 ? mem_rdata[lane*8 +: 8]:mem_rdata[7:0];
                    end
                    exec_address<=exec_address+4;
                    index<=index+(active_op==8'h15 ? 9'd1:9'd4);
                    remaining<=remaining-(active_op==8'h15 ? 24'd1:24'd4);
                    if(remaining==(active_op==8'h15 ? 24'd1:24'd4)) begin exec_state<=0;last_sequence<=active_seq;end
                    else exec_state<=1;
                end
            endcase
            if(rx_valid) case(state)
                0: if(rx_data==8'h47) begin crc<=crc_byte(16'hffff,rx_data);state<=1;end
                1: if(rx_data==1) begin crc<=crc_byte(crc,rx_data);state<=2;end else begin error<=1;state<=0;end
                2: begin opcode<=rx_data;crc<=crc_byte(crc,rx_data);state<=3;end
                3: begin seq<=rx_data;crc<=crc_byte(crc,rx_data);state<=4;end
                4,5,6,7: begin address[(state-4)*8 +: 8]<=rx_data;crc<=crc_byte(crc,rx_data);state<=state+1'b1;end
                8: begin length[7:0]<=rx_data;crc<=crc_byte(crc,rx_data);state<=9;end
                9: begin
                    crc<=crc_byte(crc,rx_data);count<=0;
                    if(rx_data>1||(rx_data==1&&length[7:0]!=0)) begin error<=2;state<=0;end
                    else begin length[8]<=rx_data[0];state<=(rx_data==0&&length[7:0]==0) ? 11:10;end
                end
                10: begin
                    if(!busy && count<5) params[count[2:0]]<=rx_data;
                    crc<=crc_byte(crc,rx_data);count<=count+1'b1;
                    if(count+1'b1==length)state<=11;
                end
                11: begin crc_low<=rx_data;state<=12;end
                12: begin
                    state<=0;
                    if({rx_data,crc_low}!=crc) error<=3;
                    else if(opcode==8'h20) status_response;
                    else if(opcode==8'h21&&!busy) begin response_data<=1;response_length<=read_length;response_index<=0;end
                    else if(opcode==1) begin run<=0;pause<=1;reset_pulse<=1;inject_enable<=0;exec_state<=0;error<=0;last_sequence<=seq;end
                    else if(busy) error<=4;
                    else begin
                        error<=0;active_op<=opcode;active_seq<=seq;last_sequence<=seq;
                        case(opcode)
                            1: begin run<=0;pause<=1;reset_pulse<=1;inject_enable<=0;end
                            2: if(length==5) begin max_rom_addr<={params[3][0],params[2],params[1],params[0]}-25'd1;flash_1m<=params[4][0];end else error<=5;
                            3: if(ram_ready&&panel_ready&&!ram_fault) begin run<=1;pause<=0;end else error<=6;
                            4: pause<=1;
                            5: pause<=0;
                            6: if(length==3) begin inject_enable<=params[0][0];injected<={params[2][1:0],params[1]};end else error<=5;
                            8'h10: if(length!=0&&length[1:0]==0&&address[31:23]==0&&address[1:0]==0&&{1'b0,address[22:0]}+{15'd0,length}<=24'h800000&&(!run||pause)) begin
                                exec_address<=address[22:0];remaining<={15'd0,length};index<=0;exec_state<=1;last_sequence<=last_sequence;
                            end else error<=5;
                            8'h12,8'h15: if(length==2&&{params[1],params[0]}!=0&&{params[1],params[0]}<=256&&(!run||pause)) begin
                                exec_address<=opcode==8'h15 ? 32'h80000+(address<<2):address;
                                remaining<={8'd0,params[1],params[0]};read_length<={params[1][0],params[0]};index<=0;exec_state<=1;last_sequence<=last_sequence;
                                if(opcode==8'h12&&(address[31:23]!=0||address[1:0]!=0||params[0][1:0]!=0||{1'b0,address[22:0]}+{15'd0,params[1][0],params[0]}>24'h800000)) begin exec_state<=0;error<=5;end
                                if(opcode==8'h15&&(address>=32'h20000||{1'b0,address[16:0]}+{9'd0,params[1][0],params[0]}>18'h20000)) begin exec_state<=0;error<=5;end
                            end else error<=5;
                            8'h14: if(length==5&&address[31:23]==0&&address[1:0]==0&&params[0][1:0]==0&&{params[3],params[2],params[1],params[0]}!=0&&{params[3],params[2],params[1],params[0]}<=32'h800000&&{1'b0,address[22:0]}+{params[2],params[1],params[0]}<=24'h800000&&(!run||pause)) begin
                                exec_address<=address[22:0];remaining<={params[2],params[1],params[0]};index<=0;exec_state<=1;last_sequence<=last_sequence;
                            end else error<=5;
                            default: error<=7;
                        endcase
                    end
                end
                default: state<=0;
            endcase
        end
    end
endmodule
