// top.v — fast streaming GC9A01 driver.
// btn[0]=image (stonks.mem, OOB-into-12kB-array preserved), btn[1]=R, btn[2]=G,
// btn[3]=B, btn[4]=pink. D12=grey. C12=async reset (active low).
module top (
    input  wire       clk_ext,
    input  wire [4:0] btn,
    input  wire       btn_grey_n,
    input  wire       btn_rst_n,
    output wire [7:0] led,
    inout  wire [7:0] interconnect,
    inout  wire [7:0] pmod_j1,
    inout  wire [7:0] pmod_j2,
    output wire       oled_scl,
    output wire       oled_sda,
    output wire       oled_dc,
    output wire       oled_cs,
    output wire       oled_rst,
    inout  wire [4:0] s
);
    localparam integer CLK_HZ = 75000000;

    localparam integer IMG_W = 96;
    localparam integer IMG_H = 64;

    // ---- Clock: OSCG /6 (~50 MHz) → PLL → 75 MHz sys_clk ----
    // Streaming SCLK = sys_clk / 2 = 37.5 MHz. Frame time = 240*240*32 /
    // 75e6 ≈ 24.6 ms (~40 fps). To push further toward 80 fps, restore the
    // ODDR-driven SCLK so it runs at full sys_clk rate (75 MHz).
    wire osc_clk;
    defparam OSCI1.DIV = "6";
    OSCG OSCI1 (.OSC(osc_clk));

    wire sys_clk, pll_locked;
    ecp5_oled_pll u_pll (
        .clki   (osc_clk),
        .clko   (sys_clk),
        .locked (pll_locked)
    );

    wire unused_clk_ext = clk_ext;

    // ---- Reset (button + sync, gated by PLL lock) ----
    wire reset_button = ~btn_rst_n;
    reg  [1:0] reset_sync = 2'b11;
    reg  [7:0] reset_counter = 0;
    wire reset_request = reset_sync[1];
    wire resetn = (&reset_counter) & pll_locked;

    always @(posedge sys_clk) begin
        reset_sync <= {reset_sync[0], reset_button};
        if (reset_request)
            reset_counter <= 0;
        else if (!(&reset_counter))
            reset_counter <= reset_counter + 1;
    end

    // ---- Buttons ----
    wire [4:0] btn_press;
    wire       grey_press;
    btn_debounce #(.WIDTH(5), .STABLE_CYCLES(4096)) u_deb (
        .clk(sys_clk), .resetn(resetn), .btn_n(btn), .btn_press(btn_press)
    );
    btn_debounce #(.WIDTH(1), .STABLE_CYCLES(4096)) u_grey (
        .clk(sys_clk), .resetn(resetn), .btn_n(btn_grey_n), .btn_press(grey_press)
    );

    // ---- Image BRAM (synchronous read) ----
    reg [15:0] image_memory [0:IMG_W*IMG_H - 1];
    initial $readmemh("stonks.mem", image_memory);

    wire [15:0] stream_pixel_index;

    // ---- Image stretcher (factored into image_stretch.v) ----
    // Mode chosen by which image-button is held (priority: btn[3] > btn[2] > btn[0]):
    //   btn[3] → CIRCLE  (image at 2x scale 192x128, fits inside the GC9A01 bezel circle)
    //   btn[2] → ASPECT  (image at 240x160 with 40px letterbox top/bottom)
    //   btn[0] → FULL    (image stretched to fill the 240x240 panel)
    wire [1:0] stretch_mode = btn_press[3] ? 2'b10 :
                              btn_press[2] ? 2'b01 :
                                             2'b00;
    wire [12:0] image_idx;
    wire        valid_pixel;
    image_stretch u_stretch (
        .clk         (sys_clk),
        .resetn      (resetn),
        .pixel_index (stream_pixel_index),
        .mode        (stretch_mode),
        .image_idx   (image_idx),
        .valid_pixel (valid_pixel)
    );

    // BRAM read; valid_pixel is pipelined to align with image_pixel_data_r.
    reg [15:0] image_pixel_data_r;
    reg        valid_pixel_r;
    always @(posedge sys_clk) begin
        image_pixel_data_r <= image_memory[image_idx];
        valid_pixel_r      <= valid_pixel;
    end

    // ---- Button-overlay mux (registered) ----
    // btn[0]: full-stretch image (240x240 fill — distorts aspect ratio)
    // btn[2]: aspect-correct image (240x160 with letterbox)
    // btn[3]: circle-fit image (192x128 centered; entirely inside the GC9A01 circle)
    //         (was blue solid color; repurposed)
    // Letterbox in btn[2]/btn[3] uses 16'h0000 (black).
    reg [15:0] pixel_to_stream;
    always @(posedge sys_clk) begin
        if      (grey_press)   pixel_to_stream <= 16'hFFE0;
        else if (btn_press[4]) pixel_to_stream <= 16'hFE19;
        else if (btn_press[3]) pixel_to_stream <= valid_pixel_r ? image_pixel_data_r : 16'h0000;
        else if (btn_press[2]) pixel_to_stream <= valid_pixel_r ? image_pixel_data_r : 16'h0000;
        else if (btn_press[1]) pixel_to_stream <= 16'hF800;
        else if (btn_press[0]) pixel_to_stream <= image_pixel_data_r;
        else                   pixel_to_stream <= 16'hFFFF;
    end

    // ---- Init module ----
    wire init_done;
    wire ramwr_pulse;
    reg  rearm;
    wire init_sclk, init_mosi, init_dc, init_cs, init_rst_n;
    oled_init #(
        .CLK_HZ      (CLK_HZ),
        .SPI_CLK_DIV (8'd4)
    ) u_init (
        .clk         (sys_clk),
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

    // ---- Stream module ----
    reg  stream_enable;
    wire stream_sclk, stream_mosi, stream_cs, stream_dc, stream_frame_done;
    oled_stream u_stream (
        .clk         (sys_clk),
        .resetn      (resetn),
        .enable      (stream_enable),
        .pixel_index (stream_pixel_index),
        .pixel_data  (pixel_to_stream),
        .sclk        (stream_sclk),
        .mosi        (stream_mosi),
        .cs          (stream_cs),
        .dc          (stream_dc),
        .frame_done  (stream_frame_done)
    );

    // ---- Sequencer FSM ----
    localparam [1:0] SEQ_WAIT_INIT = 2'd0;
    localparam [1:0] SEQ_STREAM    = 2'd1;
    localparam [1:0] SEQ_REARM     = 2'd2;
    reg [1:0] seq;

    always @(posedge sys_clk) begin
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

    // ---- Pin arbitration (ODDR-bypass debug) ----
    // Both SCLK and MOSI are driven by plain register outputs from the
    // selected module. oled_stream's `sclk` toggles every sys_clk cycle
    // when streaming → SCLK pin frequency = sys_clk/2. No ODDR primitive
    // involved, so this rules out any ODDR phase / model mismatch as the
    // cause of the panel staying dark. Restore ODDR (with sys_clk-rate
    // SCLK) once we confirm the slow path works.
    wire stream_owns = stream_enable;
    assign oled_scl = stream_owns ? stream_sclk : init_sclk;
    assign oled_sda = stream_owns ? stream_mosi : init_mosi;

    assign oled_cs  = stream_owns ? stream_cs : init_cs;
    assign oled_dc  = stream_owns ? stream_dc : init_dc;
    assign oled_rst = init_rst_n;

    // ---- Status / debug LEDs ----
    // LED[7] = init_done           — should turn on ~150 ms after FPGA boot
    // LED[6] = stream_enable       — sequencer asserted enable
    // LED[5] = u_stream.streaming  — oled_stream entered streaming state
    // LED[4] = oled_cs             — should pulse during init, low during stream
    // LED[3] = oled_dc             — high during pixel data
    // LED[2] = oled_rst            — should be high after init's RST_HI
    // LED[1] = grey_press
    // LED[0] = btn_press[0]        — image button
    assign led = {init_done, stream_enable, u_stream.streaming,
                  oled_cs, oled_dc, oled_rst, grey_press, btn_press[0]};

    // Non-OLED inout pins parked at high-Z. None of these are referenced by
    // the OLED driver modules (oled_init, oled_stream).
    assign interconnect = 8'bz;
    assign pmod_j1      = 8'bz;
    assign pmod_j2      = 8'bz;
    assign s            = 5'bz;
endmodule
