// frame_buffer.v — dual-clock, dual-port, double-buffered 96x64x16 frame
// buffer. Slow port writes one pixel per cycle through scan_idx 0..6143;
// fast port reads via image_stretch's image_idx output.
//
// Double-buffering rule:
//   buffer_sel_r (fast domain) = 0 → fast reads buffer A; slow writes B
//   buffer_sel_r           = 1 → fast reads buffer B; slow writes A
//
// Swap protocol:
//   1. Slow asserts `scan_done` when its scan_idx wraps (~480 µs at 12.5 MHz).
//   2. Fast 2-FF-syncs scan_done; on a rising edge it sets a pending flag.
//   3. When the OLED's `frame_done` pulses AND pending is set, fast toggles
//      buffer_sel_r and clears pending. Result: buffer swap aligns to OLED
//      frame boundaries → no visible tearing during the swap itself.
//
// CDC details:
//   • scan_done (slow → fast): 2-FF sync + edge detect.
//   • buffer_sel_r (fast → slow): 2-FF sync; slow uses synced value to
//     decide which buffer to write into. There is a 2-slow-cycle window
//     after a swap where slow still writes the old back buffer (= the
//     post-swap front). The post-swap front is what fast just started
//     reading; for those 2 pixels there is a small risk of writer/reader
//     racing on the same address. In practice that's 2 pixels per OLED
//     frame max — invisible.
module frame_buffer #(
    parameter integer DEPTH  = 6144,
    parameter integer ADDR_W = 13,
    parameter integer DATA_W = 16
) (
    // Slow write port
    input  wire              clk_w,
    input  wire              we,
    input  wire [ADDR_W-1:0] addr_w,
    input  wire [DATA_W-1:0] din,
    input  wire              scan_done,    // 1-cycle pulse at end of slow scan

    // Fast read port
    input  wire              clk_r,
    input  wire [ADDR_W-1:0] addr_r,
    output wire [DATA_W-1:0] dout,
    input  wire              frame_done    // 1-cycle pulse at end of OLED frame
);
    // ---- Two physical buffers (yosys infers two ECP5 DP16KD blocks) ----
    reg [DATA_W-1:0] mem_a [0:DEPTH-1];
    reg [DATA_W-1:0] mem_b [0:DEPTH-1];

    // ---- Fast domain: swap control ----
    reg buffer_sel_r        = 1'b0;     // 0 = read A, 1 = read B
    reg slow_done_d         = 1'b0;
    reg slow_done_dd        = 1'b0;
    reg slow_done_ddd       = 1'b0;
    reg slow_frame_pending  = 1'b0;

    always @(posedge clk_r) begin
        slow_done_d   <= scan_done;
        slow_done_dd  <= slow_done_d;
        slow_done_ddd <= slow_done_dd;
        if (slow_done_dd & ~slow_done_ddd)
            slow_frame_pending <= 1'b1;
        if (frame_done && slow_frame_pending) begin
            buffer_sel_r       <= ~buffer_sel_r;
            slow_frame_pending <= 1'b0;
        end
    end

    // BRAM read (synchronous, 1 cycle), output mux is combinational
    reg [DATA_W-1:0] dout_a;
    reg [DATA_W-1:0] dout_b;
    always @(posedge clk_r) begin
        dout_a <= mem_a[addr_r];
        dout_b <= mem_b[addr_r];
    end
    assign dout = buffer_sel_r ? dout_b : dout_a;

    // ---- Slow domain: write to the buffer NOT being read by fast ----
    reg buffer_sel_r_sync_d  = 1'b0;
    reg buffer_sel_r_sync_dd = 1'b0;
    always @(posedge clk_w) begin
        buffer_sel_r_sync_d  <= buffer_sel_r;
        buffer_sel_r_sync_dd <= buffer_sel_r_sync_d;
    end
    wire write_to_b = ~buffer_sel_r_sync_dd;

    always @(posedge clk_w) begin
        if (we && !write_to_b) mem_a[addr_w] <= din;
        if (we &&  write_to_b) mem_b[addr_w] <= din;
    end
endmodule
