module gc9a01 (
    input wire clk,
    input wire rst_n,
    output wire sclk,
    output wire mosi,
    output wire ncs,
    output wire dc,
    output reg done
);

    // List of bytes to send
    // You can modify this list with the data you want to transmit.
    // In this example, we'll send the values: 8'hAA, 8'h55, 8'hF0
    localparam NUM_BYTES = 11+240*120;

    localparam NUM_SETUP_BYTES = 114;
    
    reg [7:0] lcd_registers_mem [0:113];

initial begin
    // Inter Register Enable1 (FEh)
    lcd_registers_mem[0] = 8'hFE;
    lcd_registers_mem[1] = 8'h00;
    // Inter Register Enable2 (EFh)
    lcd_registers_mem[2] = 8'hEF;
    lcd_registers_mem[3] = 8'h00;
    // Display Function Control (B6h)
    lcd_registers_mem[4] = 8'hB6;
    lcd_registers_mem[5] = 8'h02;
    lcd_registers_mem[6] = 8'h00;
    lcd_registers_mem[7] = 8'h00;
    // Memory Access Control(36h)
    lcd_registers_mem[8] = 8'h36;
    lcd_registers_mem[9] = 8'h01;
    lcd_registers_mem[10] = 8'h48;
    // COLMOD: Pixel Format Set (3Ah)
    lcd_registers_mem[11] = 8'h3A;
    lcd_registers_mem[12] = 8'h01;
    lcd_registers_mem[13] = 8'h05;
    // Power Control 2 (C3h)
    lcd_registers_mem[14] = 8'hC3;
    lcd_registers_mem[15] = 8'h01;
    lcd_registers_mem[16] = 8'h13;
    // Power Control 3 (C4h)
    lcd_registers_mem[17] = 8'hC4;
    lcd_registers_mem[18] = 8'h01;
    lcd_registers_mem[19] = 8'h13;
    // Power Control 4 (C9h)
    lcd_registers_mem[20] = 8'hC9;
    lcd_registers_mem[21] = 8'h01;
    lcd_registers_mem[22] = 8'h22;
    // SET_GAMMA1 (F0h)
    lcd_registers_mem[23] = 8'hF0;
    lcd_registers_mem[24] = 8'h06;
    lcd_registers_mem[25] = 8'h45;
    lcd_registers_mem[26] = 8'h09;
    lcd_registers_mem[27] = 8'h08;
    lcd_registers_mem[28] = 8'h08;
    lcd_registers_mem[29] = 8'h26;
    lcd_registers_mem[30] = 8'h2A;
    // SET_GAMMA2 (F1h)
    lcd_registers_mem[31] = 8'hF1;
    lcd_registers_mem[32] = 8'h06;
    lcd_registers_mem[33] = 8'h43;
    lcd_registers_mem[34] = 8'h70;
    lcd_registers_mem[35] = 8'h72;
    lcd_registers_mem[36] = 8'h36;
    lcd_registers_mem[37] = 8'h37;
    lcd_registers_mem[38] = 8'h6F;
    // SET_GAMMA3 (F2h)
    lcd_registers_mem[39] = 8'hF2;
    lcd_registers_mem[40] = 8'h06;
    lcd_registers_mem[41] = 8'h45;
    lcd_registers_mem[42] = 8'h09;
    lcd_registers_mem[43] = 8'h08;
    lcd_registers_mem[44] = 8'h08;
    lcd_registers_mem[45] = 8'h26;
    lcd_registers_mem[46] = 8'h2A;
    // SET_GAMMA4 (F3h)
    lcd_registers_mem[47] = 8'hF3;
    lcd_registers_mem[48] = 8'h06;
    lcd_registers_mem[49] = 8'h43;
    lcd_registers_mem[50] = 8'h70;
    lcd_registers_mem[51] = 8'h72;
    lcd_registers_mem[52] = 8'h36;
    lcd_registers_mem[53] = 8'h37;
    lcd_registers_mem[54] = 8'h6F;
    // Custom registers
    lcd_registers_mem[55] = 8'h66;
    lcd_registers_mem[56] = 8'h0A;
    lcd_registers_mem[57] = 8'h3C;
    lcd_registers_mem[58] = 8'h00;
    lcd_registers_mem[59] = 8'hCD;
    lcd_registers_mem[60] = 8'h67;
    lcd_registers_mem[61] = 8'h45;
    lcd_registers_mem[62] = 8'h45;
    lcd_registers_mem[63] = 8'h10;
    lcd_registers_mem[64] = 8'h00;
    lcd_registers_mem[65] = 8'h00;
    lcd_registers_mem[66] = 8'h00;
    lcd_registers_mem[67] = 8'h67;
    lcd_registers_mem[68] = 8'h0A;
    lcd_registers_mem[69] = 8'h00;
    lcd_registers_mem[70] = 8'h3C;
    lcd_registers_mem[71] = 8'h00;
    lcd_registers_mem[72] = 8'h00;
    lcd_registers_mem[73] = 8'h00;
    lcd_registers_mem[74] = 8'h01;
    lcd_registers_mem[75] = 8'h54;
    lcd_registers_mem[76] = 8'h10;
    lcd_registers_mem[77] = 8'h32;
    lcd_registers_mem[78] = 8'h98;
    lcd_registers_mem[79] = 8'h74;
    lcd_registers_mem[80] = 8'h07;
    lcd_registers_mem[81] = 8'h10;
    lcd_registers_mem[82] = 8'h85;
    lcd_registers_mem[83] = 8'h80;
    lcd_registers_mem[84] = 8'h00;
    lcd_registers_mem[85] = 8'h00;
    lcd_registers_mem[86] = 8'h4E;
    lcd_registers_mem[87] = 8'h00;
    lcd_registers_mem[88] = 8'h98;
    lcd_registers_mem[89] = 8'h02;
    lcd_registers_mem[90] = 8'h3E;
    lcd_registers_mem[91] = 8'h07;
    // Tearing Effect Line ON (35h)
    lcd_registers_mem[92] = 8'h35;
    lcd_registers_mem[93] = 8'h00;
    // Display Inversion ON (21h)
    lcd_registers_mem[94] = 8'h21;
    lcd_registers_mem[95] = 8'h00;
    // Sleep Out Mode (11h) and delay(120)
    lcd_registers_mem[96] = 8'h11;
    lcd_registers_mem[97] = 8'h80;
    lcd_registers_mem[98] = 8'h78;
    // Display ON (29h) and delay(20)
    lcd_registers_mem[99] = 8'h29;
    lcd_registers_mem[100] = 8'h80;
    lcd_registers_mem[101] = 8'h14;
    // Column Address Set (2Ah)
    lcd_registers_mem[102] = 8'h2A;
    lcd_registers_mem[103] = 8'h04;
    lcd_registers_mem[104] = 8'h00;
    lcd_registers_mem[105] = 8'h00;
    lcd_registers_mem[106] = 8'h00;
    lcd_registers_mem[107] = 8'hEF;
    // Row Address Set (2Bh)
    lcd_registers_mem[108] = 8'h2B;
    lcd_registers_mem[109] = 8'h04;
    lcd_registers_mem[110] = 8'h00;
    lcd_registers_mem[111] = 8'h00;
    lcd_registers_mem[112] = 8'h00;
    lcd_registers_mem[113] = 8'hEF;
end

reg [0:0] lcd_start_bits_mem [0:113];

initial begin
    // Inter Register Enable1 (FEh)
    lcd_start_bits_mem[0] = 1'b0;
    lcd_start_bits_mem[1] = 1'b1;
    // Inter Register Enable2 (EFh)
    lcd_start_bits_mem[2] = 1'b0;
    lcd_start_bits_mem[3] = 1'b1;
    // Display Function Control (B6h)
    lcd_start_bits_mem[4] = 1'b0;
    lcd_start_bits_mem[5] = 1'b1;
    lcd_start_bits_mem[6] = 1'b1;
    lcd_start_bits_mem[7] = 1'b1;
    // Memory Access Control(36h)
    lcd_start_bits_mem[8] = 1'b0;
    lcd_start_bits_mem[9] = 1'b1;
    lcd_start_bits_mem[10] = 1'b1;
    // COLMOD: Pixel Format Set (3Ah)
    lcd_start_bits_mem[11] = 1'b0;
    lcd_start_bits_mem[12] = 1'b1;
    lcd_start_bits_mem[13] = 1'b1;
    // Power Control 2 (C3h)
    lcd_start_bits_mem[14] = 1'b0;
    lcd_start_bits_mem[15] = 1'b1;
    lcd_start_bits_mem[16] = 1'b1;
    // Power Control 3 (C4h)
    lcd_start_bits_mem[17] = 1'b0;
    lcd_start_bits_mem[18] = 1'b1;
    lcd_start_bits_mem[19] = 1'b1;
    // Power Control 4 (C9h)
    lcd_start_bits_mem[20] = 1'b0;
    lcd_start_bits_mem[21] = 1'b1;
    lcd_start_bits_mem[22] = 1'b1;
    // SET_GAMMA1 (F0h)
    lcd_start_bits_mem[23] = 1'b0;
    lcd_start_bits_mem[24] = 1'b1;
    lcd_start_bits_mem[25] = 1'b1;
    lcd_start_bits_mem[26] = 1'b1;
    lcd_start_bits_mem[27] = 1'b1;
    lcd_start_bits_mem[28] = 1'b1;
    lcd_start_bits_mem[29] = 1'b1;
    lcd_start_bits_mem[30] = 1'b1;
    // SET_GAMMA2 (F1h)
    lcd_start_bits_mem[31] = 1'b0;
    lcd_start_bits_mem[32] = 1'b1;
    lcd_start_bits_mem[33] = 1'b1;
    lcd_start_bits_mem[34] = 1'b1;
    lcd_start_bits_mem[35] = 1'b1;
    lcd_start_bits_mem[36] = 1'b1;
    lcd_start_bits_mem[37] = 1'b1;
    lcd_start_bits_mem[38] = 1'b1;
    // SET_GAMMA3 (F2h)
    lcd_start_bits_mem[39] = 1'b0;
    lcd_start_bits_mem[40] = 1'b1;
    lcd_start_bits_mem[41] = 1'b1;
    lcd_start_bits_mem[42] = 1'b1;
    lcd_start_bits_mem[43] = 1'b1;
    lcd_start_bits_mem[44] = 1'b1;
    lcd_start_bits_mem[45] = 1'b1;
    lcd_start_bits_mem[46] = 1'b1;
    // SET_GAMMA4 (F3h)
    lcd_start_bits_mem[47] = 1'b0;
    lcd_start_bits_mem[48] = 1'b1;
    lcd_start_bits_mem[49] = 1'b1;
    lcd_start_bits_mem[50] = 1'b1;
    lcd_start_bits_mem[51] = 1'b1;
    lcd_start_bits_mem[52] = 1'b1;
    lcd_start_bits_mem[53] = 1'b1;
    lcd_start_bits_mem[54] = 1'b1;
    // Custom registers
    lcd_start_bits_mem[55] = 1'b0;
    lcd_start_bits_mem[56] = 1'b1;
    lcd_start_bits_mem[57] = 1'b1;
    lcd_start_bits_mem[58] = 1'b1;
    lcd_start_bits_mem[59] = 1'b1;
    lcd_start_bits_mem[60] = 1'b1;
    lcd_start_bits_mem[61] = 1'b1;
    lcd_start_bits_mem[62] = 1'b1;
    lcd_start_bits_mem[63] = 1'b1;
    lcd_start_bits_mem[64] = 1'b1;
    lcd_start_bits_mem[65] = 1'b1;
    lcd_start_bits_mem[66] = 1'b1;
    lcd_start_bits_mem[67] = 1'b0;
    lcd_start_bits_mem[68] = 1'b1;
    lcd_start_bits_mem[69] = 1'b1;
    lcd_start_bits_mem[70] = 1'b1;
    lcd_start_bits_mem[71] = 1'b1;
    lcd_start_bits_mem[72] = 1'b1;
    lcd_start_bits_mem[73] = 1'b1;
    lcd_start_bits_mem[74] = 1'b1;
    lcd_start_bits_mem[75] = 1'b1;
    lcd_start_bits_mem[76] = 1'b1;
    lcd_start_bits_mem[77] = 1'b1;
    lcd_start_bits_mem[78] = 1'b1;
    lcd_start_bits_mem[79] = 1'b0;
    lcd_start_bits_mem[80] = 1'b1;
    lcd_start_bits_mem[81] = 1'b1;
    lcd_start_bits_mem[82] = 1'b1;
    lcd_start_bits_mem[83] = 1'b1;
    lcd_start_bits_mem[84] = 1'b1;
    lcd_start_bits_mem[85] = 1'b1;
    lcd_start_bits_mem[86] = 1'b1;
    lcd_start_bits_mem[87] = 1'b1;
    lcd_start_bits_mem[88] = 1'b0;
    lcd_start_bits_mem[89] = 1'b1;
    lcd_start_bits_mem[90] = 1'b1;
    lcd_start_bits_mem[91] = 1'b1;
    // Tearing Effect Line ON (35h)
    lcd_start_bits_mem[92] = 1'b0;
    lcd_start_bits_mem[93] = 1'b1;
    // Display Inversion ON (21h)
    lcd_start_bits_mem[94] = 1'b0;
    lcd_start_bits_mem[95] = 1'b1;
    // Sleep Out Mode (11h)
    lcd_start_bits_mem[96] = 1'b0;
    lcd_start_bits_mem[97] = 1'b1;
    lcd_start_bits_mem[98] = 1'b1;
    // Display ON (29h)
    lcd_start_bits_mem[99] = 1'b0;
    lcd_start_bits_mem[100] = 1'b1;
    lcd_start_bits_mem[101] = 1'b1;
    // Column Address Set (2Ah)
    lcd_start_bits_mem[102] = 1'b0;
    lcd_start_bits_mem[103] = 1'b1;
    lcd_start_bits_mem[104] = 1'b1;
    lcd_start_bits_mem[105] = 1'b1;
    lcd_start_bits_mem[106] = 1'b1;
    lcd_start_bits_mem[107] = 1'b1;
    // Row Address Set (2Bh)
    lcd_start_bits_mem[108] = 1'b0;
    lcd_start_bits_mem[109] = 1'b1;
    lcd_start_bits_mem[110] = 1'b1;
    lcd_start_bits_mem[111] = 1'b1;
    lcd_start_bits_mem[112] = 1'b1;
    lcd_start_bits_mem[113] = 1'b1;
end


    function [7:0] spi_command;
        input [31:0] index;
        begin
            if (index < 114) begin
                spi_command = lcd_registers_mem[index];
            end else begin
                spi_command = 8'hFF; 
                /*
                case (index-114)
                    // // to pass test cases
                    // 0: begin spi_command = 8'hAA; end
                    // 1: begin spi_command = 8'h55; end
                    // 2: begin spi_command = 8'hF0; end

                    // Set width
                    0: begin spi_command = 8'h2A; end
                    1: begin spi_command = 8'h00; end
                    2: begin spi_command = 8'h00; end
                    3: begin spi_command = 8'h00; end
                    4: begin spi_command = 8'hEF; end
                    
                    5+0: begin spi_command = 8'h2B; end
                    5+1: begin spi_command = 8'h00; end
                    5+2: begin spi_command = 8'h00; end
                    5+3: begin spi_command = 8'h00; end
                    5+4: begin spi_command = 8'hEF; end

                    10: begin spi_command = 8'h2C; end

                    default: begin spi_command = 8'hFF; end
                endcase
                */
            end
        end
    endfunction

    function spi_is_command;
        input [31:0] index;
        begin
            if (index < 114) begin
                spi_is_command = lcd_start_bits_mem[index];
            end else begin
                spi_is_command = 1'b1;
            end
        end
    endfunction
    assign dc = spi_is_command(byte_count);

    // FSM States for sequencing bytes
    localparam IDLE = 2'b00;
    localparam SEND_BYTE = 2'b01;
    localparam WAIT_TRANSFER = 2'b10;
    localparam FINISHED = 2'b11;

    // Internal Registers
    reg [1:0] state;
    reg [31:0] byte_count; // counter for bytes in the list
    reg start_transfer_reg;
    wire transfer_done_wire;

    // Instantiate the spi_master module
    spi_master spi_master_inst (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(spi_command(byte_count)),
        .start_transfer(start_transfer_reg),
        .transfer_done(transfer_done_wire),
        .sclk(sclk),
        .mosi(mosi),
        .ncs(ncs)
    );

    // Main FSM to control the byte sequence
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            byte_count <= 0;
            start_transfer_reg <= 0;
            done <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (byte_count < NUM_BYTES) begin
                        state <= SEND_BYTE;
                        done <= 0;
                    end else begin
                        state <= FINISHED; // All bytes sent
                    end
                    start_transfer_reg <= 0;
                end
                
                SEND_BYTE: begin
                    start_transfer_reg <= 1; // Assert start signal for spi_master
                    state <= WAIT_TRANSFER;
                end
                
                WAIT_TRANSFER: begin
                    start_transfer_reg <= 0; // De-assert start
                    if (transfer_done_wire) begin
                        byte_count <= byte_count + 1;
                        state <= IDLE; // Move to the next byte
                    end
                end
                
                FINISHED: begin
                    // Remain in finished state until reset
                    done <= 1;
                    state <= FINISHED;
                end
            endcase
        end
    end
endmodule
