module top #(
    parameter integer HOLD_COLOR_BARS=0,
    parameter integer PANEL_SWAP_RB=0
)(
    input wire [4:0] btn,
    input wire btn_grey_n, btn_rst_n,
    input wire debug_sck, debug_cs_n,
    output wire debug_miso,
    output wire [7:0] led,
    input wire [7:0] cam_data,
    input wire cam_pclk, cam_vsync, cam_href,
    output wire cam_xclk, cam_sioc,
    inout wire cam_siod,
    output wire cam_reset_n, cam_pwdn,
    output wire oled_scl, oled_sda, oled_dc, oled_cs, oled_rst
);
    // Conservative display/logic clock for hardware bring-up. Camera XCLK
    // stays at nominal 12.5 MHz; panel SCLK becomes nominal 25 MHz.
    localparam CLK_HZ=50000000;
    wire osc_clk, clk, locked;
    OSCG #(.DIV("6")) oscillator(.OSC(osc_clk));
    ecp5_oled_pll #(.OUTPUT_HZ(CLK_HZ)) pll(.clki(osc_clk),.clko(clk),.locked(locked));
    // Asynchronously assert and synchronously release reset in each domain.
    wire reset_request = !btn_rst_n || !locked;
    (* async_reg = "true" *) reg [2:0] reset_sync=0;
    always @(posedge clk or posedge reset_request)
        if (reset_request) reset_sync<=0;
        else reset_sync<={reset_sync[1:0],1'b1};
    wire resetn=reset_sync[2];
    (* async_reg = "true" *) reg [2:0] pclk_reset_sync=0;
    always @(posedge cam_pclk or negedge resetn)
        if (!resetn) pclk_reset_sync<=0;
        else pclk_reset_sync<={pclk_reset_sync[1:0],1'b1};

    reg [1:0] xclk_div;
    reg xclk;
    always @(posedge clk) begin
        if (!resetn) begin xclk_div<=0; xclk<=0; end
        else if (xclk_div==1) begin xclk_div<=0; xclk<=!xclk; end
        else xclk_div<=xclk_div+1'b1;
    end
    assign cam_xclk=xclk;
    assign cam_pwdn=0;
    wire scl_low, sda_low, configured, live;
    wire [2:0] config_error;
    wire [7:0] product_id, version;
    wire [7:0] last_register,last_result;
    wire [3:0] last_nacks;
    // SCCB SIOC is a single-master clock output, not a bidirectional I2C
    // clock. Drive it actively; a weak pull-up cannot clock long wiring.
    wire scan_scl_low,scan_sda_low,scan_complete;
    wire [6:0] scan_address,scan_first;
    wire [7:0] scan_count;
    wire scan_enable=|config_error;
    assign cam_sioc=!(scan_enable ? scan_scl_low : scl_low);
    assign cam_siod=(scan_enable ? scan_sda_low : sda_low) ? 1'b0 : 1'bz;
    camera_scan #(.QUARTER_CYCLES(CLK_HZ/40000)) scanner(
        .clk(clk),.resetn(resetn),.enable(scan_enable),.sda_in(cam_siod),
        .scl_low(scan_scl_low),.sda_low(scan_sda_low),.complete(scan_complete),
        .address(scan_address),.first_ack(scan_first),.ack_count(scan_count));
    ov7670_config #(.CLK_HZ(CLK_HZ),.HOLD_COLOR_BARS(HOLD_COLOR_BARS)) config_sensor(
        .clk(clk),.resetn(resetn),.sda_in(cam_siod),.scl_low(scl_low),
        .sda_low(sda_low),.sensor_reset_n(cam_reset_n),.configured(configured),
        .live(live),.error_code(config_error),.product_id(product_id),.version(version),
        .last_register(last_register),.last_result(last_result),.last_nacks(last_nacks));

    wire request_toggle, ack_toggle, write_enable, write_bank, malformed;
    wire [14:0] write_address, read_address;
    wire [15:0] write_data, read_data;
    camera_capture capture(
        .pclk(cam_pclk),.resetn(pclk_reset_sync[2]),.configured(configured),
        .data(cam_data),.href(cam_href),.vsync(cam_vsync),.ack_toggle(ack_toggle),
        .request_toggle(request_toggle),.write_enable(write_enable),
        .write_bank(write_bank),.write_address(write_address),
        .write_data(write_data),.malformed(malformed));
    wire frame_boundary, frame_valid, frame_accepted;
    camera_framebuffer framebuffer(
        .pclk(cam_pclk),.write_enable(write_enable),.write_bank(write_bank),
        .write_address(write_address),.write_data(write_data),.clk(clk),
        .resetn(resetn),.request_toggle(request_toggle),.frame_boundary(frame_boundary),
        .read_address(read_address),.read_data(read_data),.ack_toggle(ack_toggle),
        .valid(frame_valid),.frame_accepted(frame_accepted));
    wire enabled;
    wire [6:0] offset;
    camera_controls #(.DEBOUNCE_CYCLES(CLK_HZ/50)) controls(
        .clk(clk),.resetn(resetn),.frame_boundary(frame_boundary),
        .buttons_n({btn[4],btn[0],btn_grey_n}),.enabled(enabled),.offset(offset));
    wire [15:0] pixel_index, pixel_data;
    camera_viewport viewport(
        .clk(clk),.resetn(resetn),.pixel_index(pixel_index),.ram_data(read_data),
        .frame_valid(frame_valid),.enabled(enabled),.offset(offset),
        .ram_address(read_address),.pixel_data(pixel_data));
    wire display_ready, streaming;
    oled_gc9a01 #(.CLK_HZ(CLK_HZ),.SWAP_RB(PANEL_SWAP_RB)) display(
        .clk(clk),.resetn(resetn),.pixel_index(pixel_index),.pixel_data(pixel_data),
        .oled_scl(oled_scl),.oled_sda(oled_sda),.oled_dc(oled_dc),
        .oled_cs(oled_cs),.oled_rst(oled_rst),.init_done(display_ready),
        .streaming(streaming),.frame_boundary(frame_boundary));

    (* async_reg = "true" *) reg [1:0] malformed_sync;
    reg [26:0] idle_cycles;
    wire active_camera=frame_valid && idle_cycles<CLK_HZ;
    always @(posedge clk) begin
        if (!resetn) begin malformed_sync<=0; idle_cycles<=CLK_HZ; end
        else begin
            malformed_sync<={malformed_sync[0],malformed};
            if (frame_accepted) idle_cycles<=0;
            else if (idle_cycles<CLK_HZ) idle_cycles<=idle_cycles+1'b1;
        end
    end
    // A stale frame remains visible; loss of new complete frames is explicit.
    assign led={((|config_error) || (configured && !active_camera)),
                malformed_sync[1],offset[6:4],enabled,active_camera,
                (configured && display_ready)};
    wire [31:0] pclk_edges,camera_frames;
    wire [9:0] last_lines;
    wire [11:0] last_bytes;
    camera_monitor monitor(.clk(clk),.resetn(resetn),.pclk(cam_pclk),.href(cam_href),
        .vsync(cam_vsync),.pclk_edges(pclk_edges),.frames(camera_frames),
        .last_lines(last_lines),.last_bytes(last_bytes));
    reg [31:0] accepted_frames,displayed_frames;
    always @(posedge clk) begin
        if(!resetn) begin accepted_frames<=0;displayed_frames<=0;end
        else begin
            if(frame_accepted) accepted_frames<=accepted_frames+1'b1;
            if(frame_boundary) displayed_frames<=displayed_frames+1'b1;
        end
    end
    wire [7:0] flags={resetn,locked,display_ready,configured,live,frame_valid,malformed_sync[1],active_camera};
    // On initialization failure geometry is unavailable. Reuse those bytes
    // for scan results and sampled inputs / commanded output levels.
    (* async_reg="true" *) reg [7:0] pins_meta,pins_sync;
    always @(posedge clk) begin
        pins_meta<={cam_reset_n,cam_pwdn,cam_xclk,cam_sioc,cam_siod,cam_href,cam_vsync,cam_pclk};
        pins_sync<=pins_meta;
    end
    wire [31:0] geometry_or_scan=scan_enable ?
        {scan_complete,scan_first,scan_count,pins_sync,1'b0,scan_address} :
        {last_lines,10'd0,last_bytes};
    wire [255:0] debug_status={32'h43414d32,product_id,version,last_register,flags,
        last_result,4'd0,last_nacks,5'd0,config_error,led,pclk_edges,camera_frames,
        accepted_frames,displayed_frames,geometry_or_scan};
    wire [191:0] pin_counts;
    wire [11:0] pin_levels,pin_changed;
    camera_pin_monitor all_inputs(.clk(clk),.resetn(resetn),
        .pins({cam_siod,cam_data,cam_href,cam_vsync,cam_pclk}),
        .counts(pin_counts),.levels(pin_levels),.changed(pin_changed));
    camera_debug #(.STATUS_BITS(512)) debug_port(.clk(clk),.resetn(resetn),.sck(debug_sck),
        .cs_n(debug_cs_n),.status({debug_status,32'h50494e31,4'd0,pin_levels,
        4'd0,pin_changed,pin_counts}),.miso(debug_miso));
endmodule
