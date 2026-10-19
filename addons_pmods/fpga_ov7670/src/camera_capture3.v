// PCLK-domain capture with independent publication/release toggles per bank.
// A bank is immutable from publication until its synchronized release.
module camera_capture3 #(parameter WIDTH=160, HEIGHT=120)(
    input wire pclk,resetn,configured,
    input wire [7:0] data,
    input wire href,vsync,
    input wire [2:0] release_toggle,
    output reg [2:0] ready_toggle,
    output reg write_enable,
    output reg [1:0] write_bank,
    output reg [14:0] write_address,
    output reg [15:0] write_data,
    output reg malformed,
    output reg [31:0] valid_frames,malformed_frames,dropped_frames
);
    (* async_reg="true" *) reg [2:0] release_meta,release_sync;
    (* async_reg="true" *) reg [1:0] config_sync;
    reg href_d,vsync_d,active,bad,byte_phase,have_bank;
    reg [1:0] bank;
    reg [7:0] high_byte;
    reg [9:0] bytes_in_line;
    reg [8:0] lines;
    reg [14:0] address;
    wire [2:0] free_bank=~(ready_toggle^release_sync);
    always @(posedge pclk or negedge resetn) begin
        if(!resetn) begin
            release_meta<=0;release_sync<=0;config_sync<=0;ready_toggle<=0;
            href_d<=0;vsync_d<=0;active<=0;bad<=0;byte_phase<=0;have_bank<=0;
            bank<=0;high_byte<=0;bytes_in_line<=0;lines<=0;address<=0;
            write_enable<=0;write_bank<=0;write_address<=0;write_data<=0;
            malformed<=0;valid_frames<=0;malformed_frames<=0;dropped_frames<=0;
        end else begin
            release_meta<=release_toggle;release_sync<=release_meta;
            config_sync<={config_sync[0],configured};
            href_d<=href;vsync_d<=vsync;write_enable<=0;
            if(!config_sync[1]) begin active<=0;byte_phase<=0;end
            else if(vsync && !vsync_d) begin
                if(active) begin
                    if(!bad && !href && !href_d && !byte_phase &&
                       lines==HEIGHT && address==WIDTH*HEIGHT) begin
                        valid_frames<=valid_frames+1'b1;
                        if(have_bank) ready_toggle[bank]<=!ready_toggle[bank];
                        else dropped_frames<=dropped_frames+1'b1;
                    end else begin
                        malformed<=1;malformed_frames<=malformed_frames+1'b1;
                    end
                end
                active<=0;
            end else if(!vsync && vsync_d) begin
                active<=1;bad<=0;byte_phase<=0;bytes_in_line<=0;lines<=0;address<=0;
                have_bank<=|free_bank;
                bank<=free_bank[0] ? 0 : free_bank[1] ? 1 : 2;
            end else if(active && !vsync) begin
                if(href) begin
                    if(lines>=HEIGHT || bytes_in_line>=WIDTH*2) bad<=1;
                    if(bytes_in_line<WIDTH*2+1) bytes_in_line<=bytes_in_line+1'b1;
                    byte_phase<=!byte_phase;
                    if(!byte_phase) high_byte<=data;
                    else if(!bad && lines<HEIGHT && bytes_in_line<WIDTH*2) begin
                        write_enable<=have_bank;write_bank<=bank;
                        write_address<=address;write_data<={high_byte,data};
                        if(address<WIDTH*HEIGHT) address<=address+1'b1;
                    end
                end else if(href_d) begin
                    if(bytes_in_line!=WIDTH*2 || byte_phase) bad<=1;
                    if(lines<HEIGHT+1) lines<=lines+1'b1;
                    bytes_in_line<=0;byte_phase<=0;
                end
            end
        end
    end
endmodule
