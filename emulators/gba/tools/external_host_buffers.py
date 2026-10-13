"""Keep CRC packet staging and completed readback payloads in SPI PSRAM.

The existing memory port also serves reserved transport regions. Only the
current upload word and two prefetched reply words remain local. Destination
writes begin after CRC validation; invalid packets only touch scratch space.
"""
def relocate_host(s):
    start=s.index('    wire [31:0] payload_word;')
    end=s.index('    integer lane;',start)
    s=s[:start]+'''    reg [31:0] payload_word,receive_word;
    reg buffer_busy;reg [1:0] buffer_owner;
    reg [5:0] buffer_tag;
    reg [31:0] reply_words[0:1];reg [5:0] reply_tags[0:1];reg [1:0] reply_valid;
    reg staging_failed;
    wire reply_hit=reply_valid[response_index[2]]&&reply_tags[response_index[2]]==response_index[7:2];
    wire [5:0] next_reply_word=response_index[7:2]+1'b1;
'''+s[end:]
    marker='    always @(posedge clk) begin'
    task='''    task advance_transfer;
      begin
        exec_address<=exec_address+4;
        index<=index+(active_op==8'h15 ? 9'd1:9'd4);
        remaining<=remaining-(active_op==8'h15 ? 24'd1:24'd4);
        if(remaining==(active_op==8'h15 ? 24'd1:24'd4))begin exec_state<=0;last_sequence<=active_seq;end
        else exec_state<=active_op==8'h10 ? 4:1;
      end
    endtask
'''
    s=s.replace(marker,task+marker,1)
    s=s.replace('            state<=0;exec_state<=0;', '            buffer_busy<=0;reply_valid<=0;staging_failed<=0;receive_word<=0;\n            state<=0;exec_state<=0;',1)
    s=s.replace('if(!tx_valid&&response_index<response_length) begin', 'if(!tx_valid&&response_index<response_length&&(!response_data||reply_hit)) begin')
    s=s.replace('read_buffer[response_index[7:2]]', 'reply_words[response_index[2]]')
    begin=s.index('                2: if(mem_done) begin')
    end=s.index('            endcase',begin)
    s=s[:begin]+'''                2: if(mem_done&&!buffer_busy) begin
                    if(active_op==8'h12||active_op==8'h15)begin
                      if(index<8)begin
                        if(active_op==8'h12)reply_words[index[2]]<=mem_rdata;
                        else reply_words[index[2]][index[1:0]*8+:8]<=mem_rdata[7:0];
                        reply_tags[index[2]]<=index[7:2];reply_valid[index[2]]<=1;
                      end
                      mem_req<=1;mem_read<=0;mem_addr<=23'h180100+{15'd0,index[7:2],2'b00};
                      mem_wdata<=active_op==8'h12 ? mem_rdata:{4{mem_rdata[7:0]}};
                      mem_be<=active_op==8'h12 ? 4'hf:(4'b1<<index[1:0]);
                      buffer_busy<=1;buffer_owner<=2;exec_state<=3;
                    end else advance_transfer;
                end
                4: if(!buffer_busy)begin
                    mem_req<=1;mem_read<=1;mem_addr<=23'h180000+{14'd0,index};mem_be<=4'hf;
                    buffer_busy<=1;buffer_owner<=1;exec_state<=5;
                end
'''+s[end:]
    marker='            if(rx_valid) case(state)'
    engine='''            if(buffer_busy&&mem_done)begin
              buffer_busy<=0;
              case(buffer_owner)
                1:begin payload_word<=mem_rdata;exec_state<=1;end
                2:advance_transfer;
                3:begin reply_words[buffer_tag[0]]<=mem_rdata;
                    reply_tags[buffer_tag[0]]<=buffer_tag;reply_valid[buffer_tag[0]]<=1;end
              endcase
            end
            // Read ahead while the current reply is shifted by the host SPI.
            if(!busy&&!buffer_busy&&response_data&&response_index<response_length)begin
              if(!reply_hit)begin
                buffer_tag<=response_index[7:2];mem_addr<=23'h180100+{15'd0,response_index[7:2],2'b00};
                mem_req<=1;mem_read<=1;mem_be<=4'hf;buffer_busy<=1;buffer_owner<=3;
              end else if(response_index[1:0]>=2&&{next_reply_word,2'b00}<response_length&&
                  !(reply_valid[next_reply_word[0]]&&reply_tags[next_reply_word[0]]==next_reply_word))begin
                buffer_tag<=next_reply_word;mem_addr<=23'h180100+{15'd0,next_reply_word,2'b00};
                mem_req<=1;mem_read<=1;mem_be<=4'hf;buffer_busy<=1;buffer_owner<=3;
              end
            end
'''
    s=s.replace(marker,engine+marker)
    s=s.replace("count<=0;\n                    if(rx_data", "count<=0;staging_failed<=0;\n                    if(rx_data")
    s=s.replace('                10: begin', '''                10: begin
                    if(!busy&&opcode==8'h10)begin
                      receive_word[count[1:0]*8+:8]<=rx_data;
                      if(count[1:0]==3)begin
                        if(buffer_busy)staging_failed<=1;
                        else begin
                          mem_req<=1;mem_read<=0;mem_addr<=23'h180000+{15'd0,count[7:2],2'b00};
                          mem_wdata<={rx_data,receive_word[23:0]};mem_be<=4'hf;
                          buffer_busy<=1;buffer_owner<=0;
                        end
                      end
                    end''')
    s=s.replace("exec_address<=opcode==8'h15 ?", "reply_valid<=0;exec_address<=opcode==8'h15 ?")
    s=s.replace("8'h10: if(length!=0", "8'h10: if(!staging_failed&&length!=0")
    # Payload fetches use the reserved PSRAM region before each committed word.
    marker='exec_address<=address[22:0];remaining<={15\'d0,length};index<=0;exec_state<=1;'
    assert s.count(marker)==1
    s=s.replace(marker,marker.replace('exec_state<=1','exec_state<=4'))
    s=s.replace('reset_pulse<=1;inject_enable<=0;exec_state<=0;', 'reset_pulse<=1;inject_enable<=0;exec_state<=0;buffer_busy<=0;reply_valid<=0;')
    return s
