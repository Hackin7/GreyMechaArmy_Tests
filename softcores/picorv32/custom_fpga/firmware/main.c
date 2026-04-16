#include "../../picorv32/firmware/firmware.h"
#include "board_io.h"

#define FPGA_CLOCK_HZ 62000000u
#define LED_TICKS_PER_SEC 10u

static inline uint32_t read_cycle(void)
{
	uint32_t value;
	__asm__ volatile ("rdcycle %0" : "=r" (value));
	return value;
}

int msg(void);
int msg(void){
	print_str("usercode: hello from PicoRV32\n");
    print_str("edit picorv32/custom_fpga/firmware/main.c and return 0 on success.\n");
    print_str("return any non-zero value to make the testbench fail.\n");
    print_str("lmao this is so funny\n");
    print_str("LLLLL\n");
    write_leds(0xff);
    return 0;
}

int main(void)
{
	//return msg();
	uint8_t led_value = 0;
	const uint32_t tick_cycles = FPGA_CLOCK_HZ / LED_TICKS_PER_SEC;
	uint32_t next_tick = read_cycle();

	for (;;) {
		write_leds(led_value++);
		next_tick += tick_cycles;

		while ((int32_t)(read_cycle() - next_tick) < 0)
			;
	}
}
