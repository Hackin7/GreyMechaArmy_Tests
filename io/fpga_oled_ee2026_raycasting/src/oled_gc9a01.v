// oled_gc9a01.v — single-module wrapper for the GC9A01 240x240 OLED driver.
// Encapsulates the slow init path (oled_init + simple_spi_master), the fast
// streaming path (oled_stream), the inter-frame RAMWR rearm sequencer, and
// the init-vs-stream pin-arbitration mux.
//
// Usage: instantiate one of these per panel. Connect clk/resetn, drive the
// `pixel_data` input with whatever 16-bit RGB565 value should appear at the
// pixel position currently indexed by the `pixel_index` output. The user is
// responsible for providing pixel_data that matches pixel_index with low
// latency (≤ ~3 cycles). Wire the oled_* outputs to the panel pins.
module oled_gc9a01 #(
    parameter integer CLK_HZ = 75000000,
    parameter [7:0]   INIT_SPI_CLK_DIV = 8'd4,
    // Some GC9A01 panel modules ship with the MADCTL color-order bit
    // defaulted such that the host's RGB565 displays as BGR565 (R and B
    // swapped). When SWAP_RB=1 the wrapper reshuffles pixel_data bits
    // before streaming so a host RGB565 value displays correctly.
    parameter [0:0]   SWAP_RB = 1'b1
) (
    input  wire        clk,
    input  wire        resetn,

    // Pixel feed: pixel_index is the OLED linear pixel address (0..57599)
    // currently being streamed; user drives pixel_data with the RGB565 value
    // for that pixel (allowing pipeline latency for BRAM/lookup).
    output wire [15:0] pixel_index,
    input  wire [15:0] pixel_data,

    // Panel pins
    output wire        oled_scl,
    output wire        oled_sda,
    output wire        oled_dc,
    output wire        oled_cs,
    output wire        oled_rst,

    // Status (mostly for debug/LEDs)
    output wire        init_done,
    output wire        streaming,       // 1 while streaming pixel data
    output wire        frame_done       // 1-cycle pulse at end of each OLED frame
);
    // ---- Slow init path ----
    wire ramwr_pulse;
    reg  rearm;
    wire init_sclk, init_mosi, init_dc, init_cs, init_rst_n;
    oled_init #(
        .CLK_HZ      (CLK_HZ),
        .SPI_CLK_DIV (INIT_SPI_CLK_DIV)
    ) u_init (
        .clk         (clk),
        .resetn      (resetn),
        .init_done   (init_done),
        .ramwr_pulse (ramwr_pulse),
        .rearm       (rearm),
        .sclk        (init_sclk),
        .mosi        (init_mosi),
        .dc          (init_dc),
        .cs          (init_cs),
        .rst_n       (init_rst_n)
    );

    // ---- Optional R/B swap (RGB565 ↔ BGR565) ----
    wire [15:0] pixel_data_swapped = SWAP_RB
        ? {pixel_data[4:0], pixel_data[10:5], pixel_data[15:11]}
        : pixel_data;

    // ---- Fast streaming path ----
    reg  stream_enable;
    wire stream_sclk, stream_mosi, stream_cs, stream_dc, stream_frame_done;
    oled_stream u_stream (
        .clk         (clk),
        .resetn      (resetn),
        .enable      (stream_enable),
        .pixel_index (pixel_index),
        .pixel_data  (pixel_data_swapped),
        .sclk        (stream_sclk),
        .mosi        (stream_mosi),
        .cs          (stream_cs),
        .dc          (stream_dc),
        .frame_done  (stream_frame_done)
    );

    // ---- Sequencer FSM: WAIT_INIT → STREAM ⇄ REARM ----
    localparam [1:0] SEQ_WAIT_INIT = 2'd0;
    localparam [1:0] SEQ_STREAM    = 2'd1;
    localparam [1:0] SEQ_REARM     = 2'd2;
    reg [1:0] seq;

    always @(posedge clk) begin
        rearm <= 1'b0;
        if (!resetn) begin
            seq           <= SEQ_WAIT_INIT;
            stream_enable <= 1'b0;
        end else begin
            case (seq)
                SEQ_WAIT_INIT: begin
                    stream_enable <= 1'b0;
                    if (init_done)
                        seq <= SEQ_STREAM;
                end
                SEQ_STREAM: begin
                    stream_enable <= 1'b1;
                    if (stream_frame_done) begin
                        stream_enable <= 1'b0;
                        seq           <= SEQ_REARM;
                    end
                end
                SEQ_REARM: begin
                    stream_enable <= 1'b0;
                    rearm         <= 1'b1;
                    if (ramwr_pulse)
                        seq <= SEQ_STREAM;
                end
                default: seq <= SEQ_WAIT_INIT;
            endcase
        end
    end

    // ---- Pin arbitration ----
    wire stream_owns = stream_enable;
    assign oled_scl = stream_owns ? stream_sclk : init_sclk;
    assign oled_sda = stream_owns ? stream_mosi : init_mosi;
    assign oled_cs  = stream_owns ? stream_cs   : init_cs;
    assign oled_dc  = stream_owns ? stream_dc   : init_dc;
    assign oled_rst = init_rst_n;

    // Forward streaming status: take it from stream_enable (the sequencer's
    // intent) rather than reaching into u_stream's internal `streaming` reg.
    // Hierarchical references don't synthesize cleanly here.
    assign streaming  = stream_enable;
    assign frame_done = stream_frame_done;
endmodule
