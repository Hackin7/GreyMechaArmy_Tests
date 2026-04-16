#include "board_io.h"

#define LED_OUTPORT 0x10000004u

void write_leds(uint8_t value)
{
	*((volatile uint32_t*)LED_OUTPORT) = value;
}
