#include "../../picorv32/firmware/firmware.h"
#include "board_io.h"
#include "gc9a01.h"

#define FPGA_CLOCK_HZ 62000000u
#define LED_TICKS_PER_SEC 10u

static inline uint32_t read_cycle(void)
{
	uint32_t value;
	__asm__ volatile ("rdcycle %0" : "=r" (value));
	return value;
}

static void delay_cycles(uint32_t delay_cycles_count){
	int32_t next_tick = read_cycle() + delay_cycles_count;
	while ((int32_t)(read_cycle() - next_tick) < 0);
}

int main(void)
{
	print_str("GC9A01: init, RGB cycle\n");

	/* Max SPI line rate for this RTL: clk_div=0 -> f_SCLK = f_sys/2 (see simple_spi_master.v). */
	spi_init(0);
	gc9a01_init();

	for (;;) {
		gc9a01_fill_screen_rgb565(GC9A01_RGB565_RED);
		write_leds(0x01);
		delay_cycles(FPGA_CLOCK_HZ);

		gc9a01_fill_screen_rgb565(GC9A01_RGB565_BLUE);
		write_leds(0x02);
		delay_cycles(FPGA_CLOCK_HZ);

		gc9a01_fill_screen_rgb565(GC9A01_RGB565_GREEN);
		write_leds(0x04);
		delay_cycles(FPGA_CLOCK_HZ);

		gc9a01_fill_screen_rgb565_per_pixel_rgb();
		write_leds(0x07);
		delay_cycles(FPGA_CLOCK_HZ);
		
		gc9a01_fill_screen_rgb565(GC9A01_RGB565_PINK);
		write_leds(0x0F);
		delay_cycles(FPGA_CLOCK_HZ);
	}
}
