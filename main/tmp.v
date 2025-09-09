module top(
    input clk_ext, input [4:0] btn, output [7:0] led, 
    inout [7:0] interconnect, 
    inout [7:0] pmod_j1, inout [7:0] pmod_j2,
    output oled_scl,
    output oled_sda,
    output oled_dc,
    output oled_cs,
    output oled_rst,
    inout [4:0] s // secret pins
);
    /// Internal Configuration ///////////////////////////////////////////
    wire clk_int;        // Internal OSCILLATOR clock
    defparam OSCI1.DIV = "3"; // Info: Max frequency for clock '$glbnet$clk': 162.00 MHz (PASS at 103.34 MHz)
    OSCG OSCI1 (.OSC(clk_int));

    wire clk = clk_int;
    localparam CLK_FREQ = 103_340_000; // EXT CLK

    // External Oscillator Easter egg /////
    reg clk_ext_soldered = 0;
    always @ (posedge clk_ext) begin clk_ext_soldered <= 1; end

    // Clock Configuration
    reg [31:0] clk_stepdown_counter = 0;
    reg [31:0] clk_stepdown_count_val = 5;
    reg clk_stepdown;
    always @ (posedge clk) begin
        clk_stepdown_counter <= clk_stepdown_counter + 1;
        if (clk_stepdown_counter >= clk_stepdown_count_val) begin
            clk_stepdown <= ~clk_stepdown;
            clk_stepdown_counter <= 0;
        end
    end

    assign led = 8'b11111111;
    

    // Instantiate the gc9a01_driver module
    gc9a01_driver #(
        .CLK_FREQ       (CLK_FREQ),   // System clock frequency (e.g., 50 MHz)
        .SPI_FREQ       (10_000_000),   // SPI clock frequency (e.g., 10 MHz)
        .SCREEN_WIDTH   (240),          // Screen width
        .SCREEN_HEIGHT  (240)           // Screen height
    ) gc9a01_driver_inst (
        .clk            (clk),
        .reset_n        (1'b1),

        .spi_clk        (oled_scl),
        .spi_mosi       (oled_sda),
        .spi_cs_n       (oled_cs),
        .lcd_dc         (oled_dc),
        .lcd_rst_n      (oled_rst),

        .pixel_data     (16'hFFFF),
        .pixel_valid    (1'b1),
        //.pixel_ready    (o_pixel_ready),

        .start_init     (1'b1),
        .start_display  (1'b1),
        //.init_done      (o_init_done),
        //.display_busy   (o_display_busy),

        //.pixel_count    (o_pixel_count)
    );

endmodule


// GC9A01 Display Driver for FPGA
// Supports 240x240 RGB565 circular LCD display
// Uses 4-wire SPI interface

module gc9a01_driver #(
    parameter CLK_FREQ = 50_000_000,    // System clock frequency in Hz
    parameter SPI_FREQ = 10_000_000,    // SPI clock frequency in Hz
    parameter SCREEN_WIDTH = 240,
    parameter SCREEN_HEIGHT = 240
)(
    input wire clk,                     // System clock
    input wire reset_n,                 // Active low reset
    
    // SPI interface to GC9A01
    output reg spi_clk,                 // SPI clock
    output reg spi_mosi,                // SPI data out
    output reg spi_cs_n,                // SPI chip select (active low)
    output reg lcd_dc,                  // Data/Command select (0=cmd, 1=data)
    output reg lcd_rst_n,               // LCD reset (active low)
    
    // Pixel data interface
    input wire [15:0] pixel_data,       // RGB565 pixel data
    input wire pixel_valid,             // Pixel data valid
    output reg pixel_ready,             // Ready for next pixel
    
    // Control interface
    input wire start_init,              // Start initialization sequence
    input wire start_display,           // Start display update
    output reg init_done,               // Initialization complete
    output reg display_busy,            // Display update in progress
    
    // Status
    output reg [15:0] pixel_count       // Current pixel being transmitted
);

    // SPI clock divider
    localparam SPI_DIV = CLK_FREQ / (2 * SPI_FREQ);
    reg [$clog2(SPI_DIV):0] spi_div_counter;
    reg spi_clk_en;
    
    // State machine states
    localparam IDLE = 4'd0,
               RESET_PULSE = 4'd1,
               INIT_CMD = 4'd2,
               INIT_DATA = 4'd3,
               WAIT_INIT = 4'd4,
               READY = 4'd5,
               SET_WINDOW = 4'd6,
               SEND_PIXELS = 4'd7,
               WAIT_COMPLETE = 4'd8;
    
    reg [3:0] state;
    reg [3:0] next_state;
    
    // SPI transmission
    reg [7:0] spi_tx_data;
    reg [3:0] spi_bit_count;
    reg spi_tx_active;
    reg spi_tx_start;
    
    // Initialization sequence
    reg [7:0] init_cmd_index;
    reg [7:0] init_data_count;
    reg [7:0] init_delay_count;
    
    // Pixel transmission
    reg [15:0] current_pixel;
    reg pixel_byte_sel;  // 0 = high byte, 1 = low byte
    
    // Timing counters
    reg [15:0] delay_counter;
    
    // GC9A01 Initialization Commands and Data
    // Command format: {command, data_count, data_bytes..., delay_ms}
    reg [7:0] init_sequence [0:127];
    
    initial begin
        // Initialize the command sequence
        // Software Reset
        init_sequence[0] = 8'h01; init_sequence[1] = 8'h00; init_sequence[2] = 8'h78;  // SWRESET, no data, 120ms delay
        
        // Sleep Out
        init_sequence[3] = 8'h11; init_sequence[4] = 8'h00; init_sequence[5] = 8'h78;  // SLPOUT, no data, 120ms delay
        
        // Display Inversion On
        init_sequence[6] = 8'h21; init_sequence[7] = 8'h00; init_sequence[8] = 8'h00;  // INVON, no data, no delay
        
        // Pixel Format Set - 16bit/pixel
        init_sequence[9] = 8'h3A; init_sequence[10] = 8'h01; init_sequence[11] = 8'h55; init_sequence[12] = 8'h00;
        
        // Memory Access Control
        init_sequence[13] = 8'h36; init_sequence[14] = 8'h01; init_sequence[15] = 8'h00; init_sequence[16] = 8'h00;
        
        // Column Address Set (0-239)
        init_sequence[17] = 8'h2A; init_sequence[18] = 8'h04; init_sequence[19] = 8'h00; init_sequence[20] = 8'h00;
        init_sequence[21] = 8'h00; init_sequence[22] = 8'hEF; init_sequence[23] = 8'h00;
        
        // Row Address Set (0-239)  
        init_sequence[24] = 8'h2B; init_sequence[25] = 8'h04; init_sequence[26] = 8'h00; init_sequence[27] = 8'h00;
        init_sequence[28] = 8'h00; init_sequence[29] = 8'hEF; init_sequence[30] = 8'h00;
        
        // Display On
        init_sequence[31] = 8'h29; init_sequence[32] = 8'h00; init_sequence[33] = 8'h14;  // DISPON, no data, 20ms delay
        
        // End marker
        init_sequence[34] = 8'hFF;
    end
    
    // SPI Clock Generation
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            spi_div_counter <= 0;
            spi_clk_en <= 0;
        end else begin
            if (spi_div_counter >= SPI_DIV - 1) begin
                spi_div_counter <= 0;
                spi_clk_en <= 1;
            end else begin
                spi_div_counter <= spi_div_counter + 1;
                spi_clk_en <= 0;
            end
        end
    end
    
    // SPI Clock Output
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            spi_clk <= 0;
        end else if (spi_clk_en && spi_tx_active && !spi_cs_n) begin
            spi_clk <= ~spi_clk;
        end else if (spi_cs_n) begin
            spi_clk <= 0;
        end
    end
    
    // Main State Machine
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= IDLE;
            lcd_rst_n <= 0;
            spi_cs_n <= 1;
            lcd_dc <= 0;
            init_done <= 0;
            display_busy <= 0;
            pixel_ready <= 0;
            pixel_count <= 0;
            init_cmd_index <= 0;
            delay_counter <= 0;
            spi_tx_start <= 0;
        end else begin
            case (state)
                IDLE: begin
                    spi_cs_n <= 1;
                    pixel_ready <= 0;
                    display_busy <= 0;
                    
                    if (start_init) begin
                        state <= RESET_PULSE;
                        lcd_rst_n <= 0;
                        delay_counter <= 16'd1000; // 1ms reset pulse
                        init_cmd_index <= 0;
                        init_done <= 0;
                    end else if (start_display && init_done) begin
                        state <= SET_WINDOW;
                        display_busy <= 1;
                        pixel_count <= 0;
                    end
                end
                
                RESET_PULSE: begin
                    if (delay_counter > 0) begin
                        delay_counter <= delay_counter - 1;
                    end else begin
                        lcd_rst_n <= 1;
                        delay_counter <= 16'd5000; // 5ms delay after reset
                        state <= WAIT_INIT;
                    end
                end
                
                WAIT_INIT: begin
                    if (delay_counter > 0) begin
                        delay_counter <= delay_counter - 1;
                    end else begin
                        state <= INIT_CMD;
                    end
                end
                
                INIT_CMD: begin
                    if (init_sequence[init_cmd_index] == 8'hFF) begin
                        // End of initialization
                        state <= READY;
                        init_done <= 1;
                    end else begin
                        // Send command
                        lcd_dc <= 0;  // Command mode
                        spi_cs_n <= 0;
                        spi_tx_data <= init_sequence[init_cmd_index];
                        spi_tx_start <= 1;
                        init_data_count <= init_sequence[init_cmd_index + 1];
                        state <= INIT_DATA;
                    end
                end
                
                INIT_DATA: begin
                    spi_tx_start <= 0;
                    if (!spi_tx_active) begin
                        if (init_data_count > 0) begin
                            // Send data bytes
                            lcd_dc <= 1;  // Data mode
                            init_cmd_index <= init_cmd_index + 1;
                            spi_tx_data <= init_sequence[init_cmd_index + 2];
                            spi_tx_start <= 1;
                            init_data_count <= init_data_count - 1;
                        end else begin
                            // Check for delay
                            spi_cs_n <= 1;
                            init_delay_count <= init_sequence[init_cmd_index + 2];
                            if (init_delay_count > 0) begin
                                delay_counter <= {init_delay_count, 8'h00}; // Convert to cycles
                            end
                            init_cmd_index <= init_cmd_index + 3;
                            state <= (init_delay_count > 0) ? WAIT_INIT : INIT_CMD;
                        end
                    end
                end
                
                READY: begin
                    if (start_display) begin
                        state <= SET_WINDOW;
                        display_busy <= 1;
                        pixel_count <= 0;
                    end
                end
                
                SET_WINDOW: begin
                    // Set column address (2A) and row address (2B) already set during init
                    // Send memory write command (2C)
                    lcd_dc <= 0;
                    spi_cs_n <= 0;
                    spi_tx_data <= 8'h2C;  // Memory Write
                    spi_tx_start <= 1;
                    state <= SEND_PIXELS;
                    pixel_byte_sel <= 0;
                    pixel_ready <= 1;
                end
                
                SEND_PIXELS: begin
                    spi_tx_start <= 0;
                    
                    if (!spi_tx_active) begin
                        if (pixel_valid && pixel_ready) begin
                            lcd_dc <= 1;  // Data mode
                            current_pixel <= pixel_data;
                            
                            if (!pixel_byte_sel) begin
                                // Send high byte
                                spi_tx_data <= pixel_data[15:8];
                                pixel_byte_sel <= 1;
                                pixel_ready <= 0;
                            end else begin
                                // Send low byte
                                spi_tx_data <= current_pixel[7:0];
                                pixel_byte_sel <= 0;
                                pixel_ready <= 1;
                                pixel_count <= pixel_count + 1;
                                
                                // Check if all pixels sent
                                if (pixel_count >= (SCREEN_WIDTH * SCREEN_HEIGHT - 1)) begin
                                    state <= WAIT_COMPLETE;
                                    pixel_ready <= 0;
                                end
                            end
                            
                            spi_tx_start <= 1;
                        end
                    end
                end
                
                WAIT_COMPLETE: begin
                    spi_tx_start <= 0;
                    if (!spi_tx_active) begin
                        spi_cs_n <= 1;
                        display_busy <= 0;
                        state <= READY;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    // SPI Transmission Logic
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            spi_tx_active <= 0;
            spi_bit_count <= 0;
            spi_mosi <= 0;
        end else begin
            if (spi_tx_start && !spi_tx_active) begin
                spi_tx_active <= 1;
                spi_bit_count <= 8;
            end else if (spi_tx_active && spi_clk_en && spi_clk) begin
                // Transmit on rising edge of SPI clock
                spi_mosi <= spi_tx_data[spi_bit_count - 1];
                spi_bit_count <= spi_bit_count - 1;
                
                if (spi_bit_count == 1) begin
                    spi_tx_active <= 0;
                end
            end
        end
    end

endmodule
