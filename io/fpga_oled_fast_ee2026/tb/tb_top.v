// tb_top.v — integration testbench. Provides behavioral models for the
// ECP5 primitives top.v needs (OSCG, ODDRX1F), instantiates top, and sniffs
// the ACTUAL pin-level SPI traffic — so this catches ODDR phase issues,
// pin-arbitration glitches, and CS/DC misbehavior that the unit-level
// tb_oled_init / tb_oled_stream cannot see.
//
// Run from project root so $readmemh("stonks.mem") resolves correctly.
// VCD lands in tb/build/top.vcd.

`timescale 1ns / 1ps

// ====================== Behavioral ECP5 primitives ======================
//
// OSCG: emits an ungated clock. Real hardware nominal is 310 MHz / DIV
// (±15%); we ignore DIV in sim and emit a fixed period — top.v's logic
// doesn't care about the absolute frequency, only relative cycle counts.
module OSCG (output reg OSC);
    parameter DIV = "6";
    initial OSC = 1'b0;
    always #50 OSC = ~OSC;          // 10 MHz simulated (100 ns period)
endmodule

// ODDRX1F: ECP5 SDR-in / DDR-out register pair. D0 and D1 are sampled on
// the rising edge of SCLK. Output Q = D0 (latched) when SCLK is HIGH,
// Q = D1 (latched) when SCLK is LOW. RST is async clear.
module ODDRX1F (input SCLK, RST, D0, D1, output Q);
    parameter GSR = "ENABLED";
    reg d0_r = 1'b0;
    reg d1_r = 1'b0;
    always @(posedge SCLK or posedge RST) begin
        if (RST) begin
            d0_r <= 1'b0;
            d1_r <= 1'b0;
        end else begin
            d0_r <= D0;
            d1_r <= D1;
        end
    end
    assign Q = SCLK ? d0_r : d1_r;
endmodule

// ====================== DUT wiring ======================

module tb_top;
    reg       clk_ext   = 1'b0;
    reg [4:0] btn       = 5'b11111; // active-low; all unpressed
    reg       btn_grey_n = 1'b1;
    reg       btn_rst_n  = 1'b1;

    wire [7:0] led;
    wire [7:0] interconnect;
    wire [7:0] pmod_j1, pmod_j2;
    wire [4:0] s;
    wire oled_scl, oled_sda, oled_dc, oled_cs, oled_rst;

    top u_top (
        .clk_ext      (clk_ext),
        .btn          (btn),
        .btn_grey_n   (btn_grey_n),
        .btn_rst_n    (btn_rst_n),
        .led          (led),
        .interconnect (interconnect),
        .pmod_j1      (pmod_j1),
        .pmod_j2      (pmod_j2),
        .oled_scl     (oled_scl),
        .oled_sda     (oled_sda),
        .oled_dc      (oled_dc),
        .oled_cs      (oled_cs),
        .oled_rst     (oled_rst),
        .s            (s)
    );

    // Override init_module's CLK_HZ for faster sim. Reset/wait cycles
    // become small. Pause counts in the ROM are absolute and unaffected;
    // they are zeroed by the force below.
    defparam u_top.u_init.CLK_HZ      = 100_000;
    defparam u_top.u_init.SPI_CLK_DIV = 8'd1;

    // Skip init-ROM pauses for fast sim. S_INIT_PAUSE = 4'd6 in oled_init.v.
    always @(u_top.u_init.st) begin
        if (u_top.u_init.st == 4'd6)
            force u_top.u_init.pause_cnt = 24'd0;
        else
            release u_top.u_init.pause_cnt;
    end

    // ====================== Pin-level SPI sniffer ======================
    // Detects rising edge of oled_scl PIN (i.e., as the panel sees it).
    // Captures oled_sda/oled_dc/oled_cs at that instant. Packs 8 bits MSB
    // first into a byte, prints. Resets bit counter on rising oled_cs.

    reg [7:0] byte_buf = 8'd0;
    integer   bit_cnt  = 0;
    integer   byte_count = 0;
    reg       streaming_started = 1'b0;

    always @(posedge oled_scl) begin
        if (oled_cs === 1'b0) begin
            byte_buf = {byte_buf[6:0], oled_sda};
            bit_cnt  = bit_cnt + 1;
            if (bit_cnt == 8) begin
                $display("[%9t] %s 0x%02h (cs=%b dc=%b)",
                         $time,
                         oled_dc === 1'b1 ? "DAT" : "CMD",
                         byte_buf, oled_cs, oled_dc);
                byte_count = byte_count + 1;
                bit_cnt = 0;
            end
        end
    end

    always @(posedge oled_cs) begin
        if (bit_cnt != 0) begin
            $display("[%9t] *** CS rose mid-byte at bit %0d (partial 0x%02h) ***",
                     $time, bit_cnt, byte_buf);
            bit_cnt = 0;
        end
    end

    // Detect streaming start (init_done + first stream byte after RAMWR)
    always @(posedge u_top.u_init.init_done) begin
        $display("[%9t] === init_done ASSERTED (sniffed %0d bytes so far) ===",
                 $time, byte_count);
    end

    always @(posedge u_top.u_stream.sclk_active) begin
        if (!streaming_started) begin
            streaming_started = 1'b1;
            $display("[%9t] === stream sclk_active RISING (first stream cycle) ===",
                     $time);
        end
    end

    // Watch for the post-frame RAMWR rearm
    always @(posedge u_top.u_init.ramwr_pulse)
        $display("[%9t] === ramwr_pulse (rearm) ===", $time);

    initial begin
        $dumpfile("tb/build/top.vcd");
        $dumpvars(0, tb_top);
        $display("[%9t] === SIM START ===", $time);
        // Run for ~3 ms simulated time to capture init + some streaming.
        // 256 reset cycles (25.6 us) + 200 cycle RST_LO (20 us) + 1000 WAIT10
        // (100 us) + 193 bytes * (1+1)*8 cycles (~3 us at sim 10 MHz) +
        // some streaming.
        #3_000_000;
        $display("[%9t] === SIM STOP (sniffed %0d bytes total) ===",
                 $time, byte_count);
        $finish;
    end

    // Watchdog
    initial begin
        #50_000_000;
        $display("[%9t] === WATCHDOG TIMEOUT (sniffed %0d bytes) ===",
                 $time, byte_count);
        $finish;
    end
endmodule
