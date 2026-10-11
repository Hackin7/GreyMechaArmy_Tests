module gb_spi_phy (
    input wire clk, input wire reset,
    input wire spi_sck, input wire spi_mosi, input wire spi_csn,
    output wire spi_miso,
    output reg [7:0] rx_data, output reg rx_valid,
    input wire [7:0] tx_data, input wire tx_valid, output wire tx_ready
);
    reg [7:0] rx_shift_sck = 0;
    reg [2:0] rx_count_sck = 0;
    reg [7:0] rx_mailbox_sck = 0;
    reg rx_toggle_sck = 0;
    reg rx_s1, rx_s2, rx_seen;
    reg [7:0] tx_mailbox = 0;
    reg tx_toggle = 0, tx_ack_sck = 0;
    reg tx_ack_s1, tx_ack_s2;
    reg [7:0] tx_shift_sck = 0;
    reg [2:0] tx_count_sck = 0;

    always @(posedge spi_sck or posedge spi_csn) begin
        if (spi_csn) begin
            rx_count_sck <= 0;
        end else begin
            rx_shift_sck <= {rx_shift_sck[6:0], spi_mosi};
            if (rx_count_sck == 3'd7) begin
                rx_mailbox_sck <= {rx_shift_sck[6:0], spi_mosi};
                rx_toggle_sck <= ~rx_toggle_sck;
                rx_count_sck <= 0;
            end else rx_count_sck <= rx_count_sck + 1'b1;
        end
    end

    always @(negedge spi_sck or posedge spi_csn) begin
        if (spi_csn) begin
            tx_count_sck <= 0;
        end else if (tx_count_sck == 0 && tx_ack_sck != tx_toggle) begin
            tx_shift_sck <= {tx_mailbox[6:0], 1'b0};
            tx_ack_sck <= tx_toggle;
            tx_count_sck <= 1;
        end else begin
            tx_shift_sck <= {tx_shift_sck[6:0], 1'b0};
            tx_count_sck <= tx_count_sck + 1'b1;
        end
    end
    assign spi_miso = spi_csn ? 1'b0 :
                      ((tx_count_sck == 0 && tx_ack_sck != tx_toggle)
                       ? tx_mailbox[7] : tx_shift_sck[7]);

    assign tx_ready = (tx_ack_s2 == tx_toggle);
    always @(posedge clk) begin
        rx_s1 <= rx_toggle_sck; rx_s2 <= rx_s1;
        tx_ack_s1 <= tx_ack_sck; tx_ack_s2 <= tx_ack_s1;
        rx_valid <= 1'b0;
        if (reset) begin
            rx_seen <= rx_s2; tx_toggle <= tx_ack_s2;
            rx_data <= 0; tx_mailbox <= 0;
        end else begin
            if (rx_s2 != rx_seen) begin
                rx_seen <= rx_s2; rx_data <= rx_mailbox_sck; rx_valid <= 1'b1;
            end
            if (tx_valid && tx_ready) begin
                tx_mailbox <= tx_data; tx_toggle <= ~tx_toggle;
            end
        end
    end
endmodule
