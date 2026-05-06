// oled_init.v — GC9A01 init ROM walk + window setup + per-frame RAMWR.
// Uses the proven simple_spi_master.v as the SPI driver (the inline byte
// shifter we tried before had a hidden bug — confirmed empirically).
module oled_init #(
    parameter integer CLK_HZ = 50000000,
    parameter [7:0] SPI_CLK_DIV = 8'd4
) (
    input  wire clk,
    input  wire resetn,
    output reg  init_done,
    output reg  ramwr_pulse,
    input  wire rearm,
    output wire sclk,
    output wire mosi,
    output wire dc,
    output wire cs,
    output wire rst_n
);
`include "gc9a01_init_rom.vh"

    localparam integer RST_LO_CYCLES = CLK_HZ / 500;        // ~2 ms
    localparam integer WAIT10_CYCLES = (CLK_HZ / 1000) * 10;

    function automatic [7:0] win_byte(input integer k);
        case (k)
            0:  win_byte = 8'h2A;
            1:  win_byte = 8'h00;
            2:  win_byte = 8'h00;
            3:  win_byte = 8'h00;
            4:  win_byte = 8'hEF;
            5:  win_byte = 8'h2B;
            6:  win_byte = 8'h00;
            7:  win_byte = 8'h00;
            8:  win_byte = 8'h00;
            9:  win_byte = 8'hEF;
            10: win_byte = 8'h2C;
            default: win_byte = 8'h00;
        endcase
    endfunction
    function automatic win_is_data(input integer k);
        case (k)
            0, 5, 10: win_is_data = 1'b0;
            default:  win_is_data = 1'b1;
        endcase
    endfunction

    // ---- SPI master driver ----
    reg  [7:0] spi_tx_data;
    reg        spi_dc_in;
    reg        spi_keep_cs;
    reg        spi_start;
    reg        panel_rst_n;
    wire       spi_busy;
    wire       spi_done;

    simple_spi_master spi0 (
        .clk        (clk),
        .resetn     (resetn),
        .clk_div    (SPI_CLK_DIV),
        .tx_data    (spi_tx_data),
        .start      (spi_start),
        .release_cs (1'b0),
        .keep_cs    (spi_keep_cs),
        .idle_cs_n  (1'b1),
        .dc_in      (spi_dc_in),
        .rst_n_in   (panel_rst_n),
        .busy       (spi_busy),
        .done       (spi_done),
        .sclk       (sclk),
        .mosi       (mosi),
        .cs_n       (cs),
        .dc         (dc),
        .rst_n      (rst_n)
    );

    // ---- main FSM ----
    localparam [3:0] S_RST_LO        = 4'd0;
    localparam [3:0] S_RST_HI        = 4'd1;
    localparam [3:0] S_WAIT10        = 4'd2;
    localparam [3:0] S_INIT_FETCH    = 4'd3;
    localparam [3:0] S_INIT_ISSUE    = 4'd4;
    localparam [3:0] S_INIT_WAIT     = 4'd5;
    localparam [3:0] S_INIT_PAUSE    = 4'd6;
    localparam [3:0] S_WIN_ISSUE     = 4'd7;
    localparam [3:0] S_WIN_WAIT      = 4'd8;
    localparam [3:0] S_TEST_PX_ISS   = 4'd12;
    localparam [3:0] S_TEST_PX_WAIT  = 4'd13;
    localparam [3:0] S_DONE          = 4'd9;
    localparam [3:0] S_REARM_ISS     = 4'd10;
    localparam [3:0] S_REARM_WAIT    = 4'd11;

    reg [3:0]  st;
    reg [31:0] timer;
    reg [15:0] init_idx;
    reg [23:0] pause_cnt;
    reg [4:0]  win_idx;
    reg [16:0] test_px_idx;

    reg [7:0]  rom_byte_r;
    reg        rom_dc_r;
    reg [23:0] rom_pause_r;
    reg        rom_pause_nz_r;     // pre-registered (rom_pause_r != 0) to break the wide compare out of the critical path
    reg        pause_cnt_nz_r;     // same for the in-pause decrement check
    always @(posedge clk) begin
        rom_byte_r     <= gc9a01_init_byte(init_idx);
        rom_dc_r       <= gc9a01_init_is_data(init_idx);
        rom_pause_r    <= gc9a01_init_pause(init_idx);
        rom_pause_nz_r <= (gc9a01_init_pause(init_idx) != 24'd0);
        pause_cnt_nz_r <= (pause_cnt != 24'd0);
    end

    always @(posedge clk) begin
        spi_start   <= 1'b0;
        ramwr_pulse <= 1'b0;

        if (!resetn) begin
            st           <= S_RST_LO;
            timer        <= 0;
            init_idx     <= 0;
            pause_cnt    <= 0;
            win_idx      <= 0;
            test_px_idx  <= 17'd0;
            init_done    <= 1'b0;
            panel_rst_n  <= 1'b0;
            spi_dc_in    <= 1'b0;
            spi_keep_cs  <= 1'b0;
            spi_tx_data  <= 8'h00;
        end else begin
            case (st)
                S_RST_LO: begin
                    panel_rst_n <= 1'b0;
                    if (timer < RST_LO_CYCLES)
                        timer <= timer + 1;
                    else begin
                        timer <= 0;
                        st    <= S_RST_HI;
                    end
                end
                S_RST_HI: begin
                    panel_rst_n <= 1'b1;
                    st          <= S_WAIT10;
                end
                S_WAIT10: begin
                    if (timer < WAIT10_CYCLES)
                        timer <= timer + 1;
                    else begin
                        timer    <= 0;
                        init_idx <= 0;
                        st       <= S_INIT_FETCH;
                    end
                end
                S_INIT_FETCH: st <= S_INIT_ISSUE;
                S_INIT_ISSUE: begin
                    if (!spi_busy) begin
                        spi_tx_data <= rom_byte_r;
                        spi_dc_in   <= rom_dc_r;
                        spi_keep_cs <= 1'b0;
                        spi_start   <= 1'b1;
                        st          <= S_INIT_WAIT;
                    end
                end
                S_INIT_WAIT: begin
                    if (spi_done) begin
                        if (rom_pause_nz_r) begin
                            pause_cnt <= rom_pause_r;
                            st        <= S_INIT_PAUSE;
                        end else begin
                            if (init_idx + 1 == GC9A01_INIT_LEN) begin
                                win_idx <= 0;
                                st      <= S_WIN_ISSUE;
                            end else begin
                                init_idx <= init_idx + 1;
                                st       <= S_INIT_FETCH;
                            end
                        end
                    end
                end
                S_INIT_PAUSE: begin
                    if (pause_cnt_nz_r)
                        pause_cnt <= pause_cnt - 1;
                    else begin
                        if (init_idx + 1 == GC9A01_INIT_LEN) begin
                            win_idx <= 0;
                            st      <= S_WIN_ISSUE;
                        end else begin
                            init_idx <= init_idx + 1;
                            st       <= S_INIT_FETCH;
                        end
                    end
                end
                S_WIN_ISSUE: begin
                    if (!spi_busy) begin
                        spi_tx_data <= win_byte(win_idx);
                        spi_dc_in   <= win_is_data(win_idx);
                        spi_keep_cs <= 1'b0;
                        spi_start   <= 1'b1;
                        st          <= S_WIN_WAIT;
                    end
                end
                S_WIN_WAIT: begin
                    if (spi_done) begin
                        if (win_idx == 5'd10) begin
                            init_done <= 1'b1;
                            st        <= S_DONE;
                        end else begin
                            win_idx <= win_idx + 1;
                            st      <= S_WIN_ISSUE;
                        end
                    end
                end
                S_DONE: begin
                    if (rearm)
                        st <= S_REARM_ISS;
                end
                S_REARM_ISS: begin
                    if (!spi_busy) begin
                        spi_tx_data <= 8'h2C;
                        spi_dc_in   <= 1'b0;
                        spi_keep_cs <= 1'b0;
                        spi_start   <= 1'b1;
                        st          <= S_REARM_WAIT;
                    end
                end
                S_REARM_WAIT: begin
                    if (spi_done) begin
                        ramwr_pulse <= 1'b1;
                        st          <= S_DONE;
                    end
                end
                default: st <= S_RST_LO;
            endcase
        end
    end
endmodule
