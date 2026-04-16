/*
 * GC9A01 240x240 round display — init sequence from Bodmer TFT_eSPI
 * TFT_Drivers/GC9A01_Init.h (MIT / project license).
 */

#include "board_clock.h"
#include "board_io.h"
#include "gc9a01.h"

void gc9a01_delay_ms(uint32_t ms)
{
	volatile uint32_t a;
	while (ms-- != 0u) {
		for (a = 0; a < GC9A01_DELAY_INNER_LOOPS_PER_MS; a++)
			;
	}
}

static void wr_cmd(uint8_t c)
{
	spi_set_dc_command();
	spi_write_byte(c, 0);
}

static void wr_data(uint8_t d)
{
	spi_set_dc_data();
	spi_write_byte(d, 0);
}

static void gc9a01_init_regs(void)
{
	wr_cmd(0xEFu);
	wr_cmd(0xEBu);
	wr_data(0x14u);

	wr_cmd(0xFEu);
	wr_cmd(0xEFu);

	wr_cmd(0xEBu);
	wr_data(0x14u);

	wr_cmd(0x84u);
	wr_data(0x40u);

	wr_cmd(0x85u);
	wr_data(0xFFu);

	wr_cmd(0x86u);
	wr_data(0xFFu);

	wr_cmd(0x87u);
	wr_data(0xFFu);

	wr_cmd(0x88u);
	wr_data(0x0Au);

	wr_cmd(0x89u);
	wr_data(0x21u);

	wr_cmd(0x8Au);
	wr_data(0x00u);

	wr_cmd(0x8Bu);
	wr_data(0x80u);

	wr_cmd(0x8Cu);
	wr_data(0x01u);

	wr_cmd(0x8Du);
	wr_data(0x01u);

	wr_cmd(0x8Eu);
	wr_data(0xFFu);

	wr_cmd(0x8Fu);
	wr_data(0xFFu);

	wr_cmd(0xB6u);
	wr_data(0x00u);
	wr_data(0x20u);

	wr_cmd(0x3Au);
	wr_data(0x05u); /* 16-bit/pixel */

	wr_cmd(0x90u);
	wr_data(0x08u);
	wr_data(0x08u);
	wr_data(0x08u);
	wr_data(0x08u);

	wr_cmd(0xBDu);
	wr_data(0x06u);

	wr_cmd(0xBCu);
	wr_data(0x00u);

	wr_cmd(0xFFu);
	wr_data(0x60u);
	wr_data(0x01u);
	wr_data(0x04u);

	wr_cmd(0xC3u);
	wr_data(0x13u);

	wr_cmd(0xC4u);
	wr_data(0x13u);

	wr_cmd(0xC9u);
	wr_data(0x22u);

	wr_cmd(0xBEu);
	wr_data(0x11u);

	wr_cmd(0xE1u);
	wr_data(0x10u);
	wr_data(0x0Eu);

	wr_cmd(0xDFu);
	wr_data(0x21u);
	wr_data(0x0Cu);
	wr_data(0x02u);

	wr_cmd(0xF0u);
	wr_data(0x45u);
	wr_data(0x09u);
	wr_data(0x08u);
	wr_data(0x08u);
	wr_data(0x26u);
	wr_data(0x2Au);

	wr_cmd(0xF1u);
	wr_data(0x43u);
	wr_data(0x70u);
	wr_data(0x72u);
	wr_data(0x36u);
	wr_data(0x37u);
	wr_data(0x6Fu);

	wr_cmd(0xF2u);
	wr_data(0x45u);
	wr_data(0x09u);
	wr_data(0x08u);
	wr_data(0x08u);
	wr_data(0x26u);
	wr_data(0x2Au);

	wr_cmd(0xF3u);
	wr_data(0x43u);
	wr_data(0x70u);
	wr_data(0x72u);
	wr_data(0x36u);
	wr_data(0x37u);
	wr_data(0x6Fu);

	wr_cmd(0xEDu);
	wr_data(0x1Bu);
	wr_data(0x0Bu);

	wr_cmd(0xAEu);
	wr_data(0x77u);

	wr_cmd(0xCDu);
	wr_data(0x63u);

	wr_cmd(0x70u);
	wr_data(0x07u);
	wr_data(0x07u);
	wr_data(0x04u);
	wr_data(0x0Eu);
	wr_data(0x0Fu);
	wr_data(0x09u);
	wr_data(0x07u);
	wr_data(0x08u);
	wr_data(0x03u);

	wr_cmd(0xE8u);
	wr_data(0x34u);

	wr_cmd(0x62u);
	wr_data(0x18u);
	wr_data(0x0Du);
	wr_data(0x71u);
	wr_data(0xEDu);
	wr_data(0x70u);
	wr_data(0x70u);
	wr_data(0x18u);
	wr_data(0x0Fu);
	wr_data(0x71u);
	wr_data(0xEFu);
	wr_data(0x70u);
	wr_data(0x70u);

	wr_cmd(0x63u);
	wr_data(0x18u);
	wr_data(0x11u);
	wr_data(0x71u);
	wr_data(0xF1u);
	wr_data(0x70u);
	wr_data(0x70u);
	wr_data(0x18u);
	wr_data(0x13u);
	wr_data(0x71u);
	wr_data(0xF3u);
	wr_data(0x70u);
	wr_data(0x70u);

	wr_cmd(0x64u);
	wr_data(0x28u);
	wr_data(0x29u);
	wr_data(0xF1u);
	wr_data(0x01u);
	wr_data(0xF1u);
	wr_data(0x00u);
	wr_data(0x07u);

	wr_cmd(0x66u);
	wr_data(0x3Cu);
	wr_data(0x00u);
	wr_data(0xCDu);
	wr_data(0x67u);
	wr_data(0x45u);
	wr_data(0x45u);
	wr_data(0x10u);
	wr_data(0x00u);
	wr_data(0x00u);
	wr_data(0x00u);

	wr_cmd(0x67u);
	wr_data(0x00u);
	wr_data(0x3Cu);
	wr_data(0x00u);
	wr_data(0x00u);
	wr_data(0x00u);
	wr_data(0x01u);
	wr_data(0x54u);
	wr_data(0x10u);
	wr_data(0x32u);
	wr_data(0x98u);

	wr_cmd(0x74u);
	wr_data(0x10u);
	wr_data(0x85u);
	wr_data(0x80u);
	wr_data(0x00u);
	wr_data(0x00u);
	wr_data(0x4Eu);
	wr_data(0x00u);

	wr_cmd(0x98u);
	wr_data(0x3Eu);
	wr_data(0x07u);

	wr_cmd(0x35u);
	wr_cmd(0x21u);

	wr_cmd(0x11u);
	gc9a01_delay_ms(120u);

	wr_cmd(0x29u);
	gc9a01_delay_ms(20u);
}

void gc9a01_init(void)
{
	spi_oled_reset_pulse();
	gc9a01_delay_ms(10u);
	gc9a01_init_regs();
}

/* CASET: column 0..239, RASET: row 0..239 (big-endian 16-bit each) */
static void gc9a01_set_full_window(void)
{
	wr_cmd(0x2Au);
	wr_data(0x00u);
	wr_data(0x00u);
	wr_data(0x00u);
	wr_data(0xEFu);

	wr_cmd(0x2Bu);
	wr_data(0x00u);
	wr_data(0x00u);
	wr_data(0x00u);
	wr_data(0xEFu);
}

void gc9a01_fill_screen_rgb565(uint16_t rgb565)
{
	uint32_t pixels = 240u * 240u;
	uint32_t i;
	uint8_t hi = (uint8_t)(rgb565 >> 8);
	uint8_t lo = (uint8_t)(rgb565 & 0xFFu);

	gc9a01_set_full_window();

	wr_cmd(0x2Cu);
	spi_set_dc_data();

	for (i = 0; i < pixels; i++) {
		uint32_t last_px = (i + 1u == pixels);
		spi_write_byte(hi, 1);
		spi_write_byte(lo, last_px ? 0 : 1);
	}
}

void gc9a01_fill_screen_rgb565_per_pixel_rgb(void)
{
	uint32_t pixels = 240u * 240u;
	uint32_t i;

	gc9a01_set_full_window();

	wr_cmd(0x2Cu);
	spi_set_dc_data();

	for (i = 0; i < pixels; i++) {
		uint16_t rgb565;
		uint8_t hi;
		uint8_t lo;
		uint32_t last_px = (i + 1u == pixels);

		switch (i % 3u) {
		case 0u:
			rgb565 = GC9A01_RGB565_RED;
			break;
		case 1u:
			rgb565 = GC9A01_RGB565_GREEN;
			break;
		default:
			rgb565 = GC9A01_RGB565_BLUE;
			break;
		}
		hi = (uint8_t)(rgb565 >> 8);
		lo = (uint8_t)(rgb565 & 0xFFu);
		spi_write_byte(hi, 1);
		spi_write_byte(lo, last_px ? 0 : 1);
	}
}
