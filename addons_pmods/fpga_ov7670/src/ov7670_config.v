// FPGA-owned sensor boot. Register table follows the OV7670 RGB565/DCW
// pipeline: VGA window -> 4x downsample -> 160x120, MSB-first RGB565.
module ov7670_config #(
    parameter integer CLK_HZ=75000000,
    // 10 kHz configuration tolerates cable capacitance and weak SDA pull-ups.
    parameter integer QUARTER_CYCLES=(CLK_HZ+39999)/40000,
    parameter integer RESET_CYCLES=CLK_HZ/200,
    parameter integer SETTLE_CYCLES=CLK_HZ/50,
    parameter integer BAR_CYCLES=CLK_HZ*2,
    parameter integer HOLD_COLOR_BARS=0
)(
    input wire clk, resetn, sda_in,
    output wire scl_low, sda_low,
    output reg sensor_reset_n,
    output reg configured, live,
    output reg [2:0] error_code, // 1=SCCB NACK, 2=PID, 3=version
    output reg [7:0] product_id, version,
    output reg [7:0] last_register, last_result,
    output reg [3:0] last_nacks
);
    localparam TABLE_LEN=74;
    function [15:0] setting(input [6:0] index);
        case(index)
            0: setting=16'h1101; // CLKRC /2, conservative PCLK
            1: setting=16'h6b0a; // bypass internal PLL
            2: setting=16'h1204; // RGB, full VGA window before DCW
            3: setting=16'h0c04; // enable DCW
            4: setting=16'h3e1a; // manual scaling, PCLK /4
            5: setting=16'h703a; // SCALING_XSC, no test-pattern bit
            6: setting=16'h7135; // SCALING_YSC
            7: setting=16'h7222; // horizontal and vertical /4
            8: setting=16'h73f2; // SCALING_PCLK_DIV /4
            9: setting=16'ha202; // SCALING_PCLK_DELAY
            10: setting=16'h1716; // HSTART: DCW-aligned 640-clock window
            11: setting=16'h1804; // HSTOP (wraps)
            12: setting=16'h3224; // start/stop low bits both 4
            13: setting=16'h1902; // VSTART
            14: setting=16'h1a7a; // VSTOP
            15: setting=16'h030a; // VREF
            16: setting=16'h1500; // PCLK free-running, VSYNC positive
            17: setting=16'h40d0; // full-range RGB565
            18: setting=16'h3a04; // TSLB default byte ordering
            19: setting=16'h3dc0; // COM13 gamma + UV saturation
            20: setting=16'h8c00; // disable RGB444
            21: setting=16'h1418; // AGC ceiling
            22: setting=16'h4f80; // RGB colour matrix
            23: setting=16'h5080;
            24: setting=16'h5100;
            25: setting=16'h5222;
            26: setting=16'h535e;
            27: setting=16'h5480;
            28: setting=16'h589e;
            29: setting=16'h7a20; // gamma curve
            30: setting=16'h7b10;
            31: setting=16'h7c1e;
            32: setting=16'h7d35;
            33: setting=16'h7e5a;
            34: setting=16'h7f69;
            35: setting=16'h8076;
            36: setting=16'h8180;
            37: setting=16'h8288;
            38: setting=16'h838f;
            39: setting=16'h8496;
            40: setting=16'h85a3;
            41: setting=16'h86af;
            42: setting=16'h87c4;
            43: setting=16'h88d7;
            44: setting=16'h89e8;
            45: setting=16'h13e0; // temporarily disable auto exposure/gain/WB
            46: setting=16'h0000;
            47: setting=16'h1000;
            48: setting=16'h0d40;
            49: setting=16'ha505;
            50: setting=16'hab07;
            51: setting=16'h2495;
            52: setting=16'h2533;
            53: setting=16'h26e3;
            54: setting=16'h9f78;
            55: setting=16'ha068;
            56: setting=16'ha103;
            57: setting=16'ha6d8;
            58: setting=16'ha7d8;
            59: setting=16'ha8f0;
            60: setting=16'ha990;
            61: setting=16'haa94;
            62: setting=16'h430a; // AWB defaults
            63: setting=16'h44f0;
            64: setting=16'h4534;
            65: setting=16'h4658;
            66: setting=16'h4728;
            67: setting=16'h483a;
            68: setting=16'h6a40;
            69: setting=16'h0100; // blue gain (AWB will update)
            70: setting=16'h0200; // red gain
            71: setting=16'h4108; // COM16 AWB gain
            72: setting=16'h13e7; // enable AEC/AGC/AWB
            73: setting=16'h4208; // COM17 sensor colour bars
            default: setting=16'h4200;
        endcase
    endfunction
    localparam RESET=0, SETTLE=1, ISSUE=2, WAIT_RESULT=3,
        SOFT_WAIT=4, BARS=5, READY=6, FAILED=7, RETRY_WAIT=8;
    reg [3:0] state;
    reg [6:0] operation; // 0=soft reset, 1=PID, 2=VER, 3..table+2, then live
    reg [31:0] timer;
    reg [1:0] retry;
    reg start;
    wire done, bus_error, busy;
    wire [7:0] result;
    wire [3:0] bus_nacks;
    wire [15:0] pair = setting(operation-7'd3);
    wire [7:0] reg_address = operation==0 ? 8'h12 : operation==1 ? 8'h0a :
        operation==2 ? 8'h0b : operation==TABLE_LEN+3 ? 8'h42 : pair[15:8];
    wire [7:0] reg_value = operation==0 ? 8'h80 :
        operation==TABLE_LEN+3 ? 8'h00 : pair[7:0];
    sccb_register #(.QUARTER_CYCLES(QUARTER_CYCLES)) bus(
        .clk(clk),.resetn(resetn),.start(start),
        .read_register(operation==1 || operation==2),
        .address(reg_address),.value(reg_value),.sda_in(sda_in),
        .scl_low(scl_low),.sda_low(sda_low),.busy(busy),
        .done(done),.error(bus_error),.result(result),.nack_mask(bus_nacks));
    always @(posedge clk) begin
        start<=0;
        if (!resetn) begin
            sensor_reset_n<=0; configured<=0; live<=0; error_code<=0;
            product_id<=0; version<=0; timer<=0; operation<=0;
            last_register<=0; last_result<=0; last_nacks<=0;
            state<=RESET; retry<=0;
        end else case(state)
            RESET: if (timer==RESET_CYCLES-1) begin
                sensor_reset_n<=1; timer<=0; state<=SETTLE;
            end else timer<=timer+1'b1;
            SETTLE, SOFT_WAIT, RETRY_WAIT:
                if (timer==SETTLE_CYCLES-1) begin timer<=0; state<=ISSUE; end
                else timer<=timer+1'b1;
            ISSUE: begin start<=1; state<=WAIT_RESULT; end
            WAIT_RESULT: if (done) begin
                last_register<=reg_address; last_result<=result;
                last_nacks<=bus_nacks;
                if (bus_error) begin
                    if (retry==2) begin error_code<=1; state<=FAILED; end
                    else begin retry<=retry+1'b1; timer<=0; state<=RETRY_WAIT; end
                end else if (operation==1 && result!=8'h76) begin
                    product_id<=result; error_code<=2; state<=FAILED;
                end else if (operation==2 && result!=8'h73) begin
                    version<=result; error_code<=3; state<=FAILED;
                end else begin
                    retry<=0; operation<=operation+1'b1;
                    if (operation==1) product_id<=result;
                    if (operation==2) version<=result;
                    if (operation==0) begin timer<=0; state<=SOFT_WAIT; end
                    else if (operation==TABLE_LEN+2) begin
                        configured<=1; timer<=0; state<=BARS;
                    end else if (operation==TABLE_LEN+3) begin live<=1; state<=READY; end
                    else state<=ISSUE;
                end
            end
            BARS: if (!HOLD_COLOR_BARS) begin
                if (timer==BAR_CYCLES-1) begin timer<=0; state<=ISSUE; end
                else timer<=timer+1'b1;
            end
            READY: ;
            FAILED: ; // Reset button retries initialization.
            default: state<=RESET;
        endcase
    end
endmodule
