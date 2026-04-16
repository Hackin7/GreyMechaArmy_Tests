#ifndef CUSTOM_FPGA_SPI_BOARD_IO_H
#define CUSTOM_FPGA_SPI_BOARD_IO_H

#include <stdint.h>

void write_leds(uint8_t value);

void spi_init(uint8_t clk_div);
void spi_oled_reset_pulse(void);
void spi_set_dc_command(void);
void spi_set_dc_data(void);
void spi_write_byte(uint8_t b, int keep_cs_after);

#endif
