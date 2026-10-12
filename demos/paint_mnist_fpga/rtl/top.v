module top (
    input wire clk_ext,
    input wire [4:0] btn,
    input wire btn_grey_n, btn_rst_n,
    output wire [7:0] led,
    inout wire [7:0] interconnect, pmod_j1, pmod_j2,
    output wire oled_scl, oled_sda, oled_dc, oled_cs, oled_rst,
    inout wire [4:0] s
);
    wire osc_clk, ui_clk, nn_clk, locked;
    defparam osc.DIV="6";
    OSCG osc(.OSC(osc_clk));
    paint_pll pll(.clki(osc_clk), .ui_clk(ui_clk), .nn_clk(nn_clk), .locked(locked));
    reg [7:0] ui_reset_count=0, nn_reset_count=0;
    wire resetn_ui = (&ui_reset_count) && locked;
    wire resetn_nn = (&nn_reset_count) && locked;
    always @(posedge ui_clk) begin
        if (!locked) ui_reset_count<=0;
        else if (!(&ui_reset_count)) ui_reset_count<=ui_reset_count+1'b1;
    end
    always @(posedge nn_clk) begin
        if (!locked) nn_reset_count<=0;
        else if (!(&nn_reset_count)) nn_reset_count<=nn_reset_count+1'b1;
    end
    wire [15:0] pixel_index, pixel_data;
    wire [3:0] prediction;
    wire prediction_valid, busy, updating, init_done, streaming;
    paint_app app (
        .ui_clk(ui_clk), .nn_clk(nn_clk), .resetn_ui(resetn_ui), .resetn_nn(resetn_nn),
        .buttons_n({btn_rst_n,btn_grey_n,btn[4],btn[3],btn[1],btn[0]}),
        .pixel_index(pixel_index), .pixel_data(pixel_data), .prediction(prediction),
        .prediction_valid(prediction_valid), .busy(busy), .updating(updating)
    );
    oled_gc9a01 #(.CLK_HZ(75000000), .INIT_SPI_CLK_DIV(8'd4)) display (
        .clk(ui_clk), .resetn(resetn_ui), .pixel_index(pixel_index), .pixel_data(pixel_data),
        .oled_scl(oled_scl), .oled_sda(oled_sda), .oled_dc(oled_dc), .oled_cs(oled_cs),
        .oled_rst(oled_rst), .init_done(init_done), .streaming(streaming)
    );
    assign led={init_done,busy,updating,prediction_valid,prediction};
    assign interconnect=8'bz;
    assign pmod_j1=8'bz;
    assign pmod_j2=8'bz;
    assign s=5'bz;
    wire unused=clk_ext | btn[2] | streaming;
endmodule
