module top #(
    parameter integer HOLD_COLOR_BARS=0,
    parameter integer PANEL_SWAP_RB=1,
    parameter integer TIMING_PROFILE=2
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
    ov7670_config #(.CLK_HZ(CLK_HZ),.HOLD_COLOR_BARS(HOLD_COLOR_BARS),.TIMING_PROFILE(TIMING_PROFILE)) config_sensor(
        .clk(clk),.resetn(resetn),.sda_in(cam_siod),.scl_low(scl_low),
        .sda_low(sda_low),.sensor_reset_n(cam_reset_n),.configured(configured),
        .live(live),.error_code(config_error),.product_id(product_id),.version(version),
        .last_register(last_register),.last_result(last_result),.last_nacks(last_nacks));

    wire [2:0] ready_toggle,release_toggle;
    wire write_enable,malformed;
    wire [1:0] write_bank,read_bank;
    wire [14:0] write_address,read_address;
    wire [15:0] write_data,read_data;
    wire [31:0] valid_pclk,malformed_pclk,dropped_pclk;
    wire [31:0] valid_frames,malformed_frames,dropped_frames,replaced_frames;
    camera_capture3 capture(.pclk(cam_pclk),.resetn(pclk_reset_sync[2]),
        .configured(configured),.data(cam_data),.href(cam_href),.vsync(cam_vsync),
        .release_toggle(release_toggle),.ready_toggle(ready_toggle),
        .write_enable(write_enable),.write_bank(write_bank),.write_address(write_address),
        .write_data(write_data),.malformed(malformed),.valid_frames(valid_pclk),
        .malformed_frames(malformed_pclk),.dropped_frames(dropped_pclk));
    camera_counter_sync valid_counter(.source_clk(cam_pclk),.source_resetn(pclk_reset_sync[2]),
        .clk(clk),.resetn(resetn),.binary(valid_pclk),.value(valid_frames));
    camera_counter_sync malformed_counter(.source_clk(cam_pclk),.source_resetn(pclk_reset_sync[2]),
        .clk(clk),.resetn(resetn),.binary(malformed_pclk),.value(malformed_frames));
    camera_counter_sync dropped_counter(.source_clk(cam_pclk),.source_resetn(pclk_reset_sync[2]),
        .clk(clk),.resetn(resetn),.binary(dropped_pclk),.value(dropped_frames));
    wire frame_boundary,frame_start,frame_valid,frame_accepted,pending_valid,display_busy;
    camera_queue3 ownership(.clk(clk),.resetn(resetn),.ready_toggle(ready_toggle),
        .display_start(frame_start),.display_done(frame_boundary),
        .release_toggle(release_toggle),.pending_valid(pending_valid),
        .display_busy(display_busy),.read_bank(read_bank),.valid(frame_valid),
        .frame_accepted(frame_accepted),.replaced_frames(replaced_frames));
    camera_ram3 framebuffer(.pclk(cam_pclk),.write_enable(write_enable),
        .write_bank(write_bank),.write_address(write_address),.write_data(write_data),
        .clk(clk),.read_bank(read_bank),.read_address(read_address),.read_data(read_data));
    wire enabled;
    wire [2:0] isp_mode;
    wire [39:0] isp_presets;
    wire [15:0] isp_value;
    wire [31:0] pixel_wait_cycles;
    isp_controls #(.DEBOUNCE_CYCLES(CLK_HZ/50)) controls(
        .clk(clk),.resetn(resetn),.commit(frame_start),
        .buttons_n({btn[3],btn[1],btn[4],btn[0],btn_grey_n}),
        .enabled(enabled),.mode(isp_mode),.presets(isp_presets),.value_q8(isp_value));
    wire display_ready, streaming;
    isp_panel #(.CLK_HZ(CLK_HZ),.SWAP_RB(PANEL_SWAP_RB)) display(
        .clk(clk),.resetn(resetn),.frame_available(pending_valid && !display_busy),
        .read_address(read_address),.read_data(read_data),.frame_start(frame_start),
        .enabled(enabled),.mode(isp_mode),.presets(isp_presets),.value_q8(isp_value),
        .pixel_wait_cycles(pixel_wait_cycles),
        .oled_scl(oled_scl),.oled_sda(oled_sda),.oled_dc(oled_dc),
        .oled_cs(oled_cs),.oled_rst(oled_rst),.init_done(display_ready),
        .streaming(streaming),.frame_done(frame_boundary));
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
                malformed_sync[1],isp_mode,enabled,active_camera,
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
    wire [255:0] rate_status={32'h46505331,32'd0 | TIMING_PROFILE,valid_frames,
        malformed_frames,dropped_frames,replaced_frames,accepted_frames,displayed_frames};
    wire [127:0] color_samples;
    camera_color_probe color_probe(.pclk(cam_pclk),.presetn(pclk_reset_sync[2]),
        .clk(clk),.resetn(resetn),.write_enable(write_enable),
        .write_address(write_address),.write_data(write_data),
        .frame_toggle(valid_pclk[0]),.samples(color_samples));
    wire [159:0] isp_status={32'h49535031,5'd0,isp_mode,7'd0,enabled,
        isp_presets[7:0],isp_presets[15:8],isp_presets[23:16],isp_presets[31:24],isp_presets[39:32],
        isp_value,8'd0,pixel_wait_cycles,16'd0};
    camera_debug #(.STATUS_BITS(1088)) debug_port(.clk(clk),.resetn(resetn),.sck(debug_sck),
        .cs_n(debug_cs_n),.status({debug_status,32'h50494e31,4'd0,pin_levels,
        4'd0,pin_changed,pin_counts,rate_status,32'h434f4c31,color_samples,isp_status}),.miso(debug_miso));
endmodule
