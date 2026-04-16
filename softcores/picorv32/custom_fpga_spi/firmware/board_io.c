#include "board_io.h"

#define LED_OUTPORT   0x10000004u
#define SPI_TX_ADDR   0x10000010u
#define SPI_CTRL_ADDR 0x10000014u
#define SPI_STATUS_ADDR 0x10000018u

#define SPI_STA_BUSY  (1u << 0)

static volatile uint32_t *const led_reg     = (volatile uint32_t *)LED_OUTPORT;
static volatile uint32_t *const spi_tx      = (volatile uint32_t *)SPI_TX_ADDR;
static volatile uint32_t *const spi_ctrl      = (volatile uint32_t *)SPI_CTRL_ADDR;
static volatile uint32_t *const spi_status   = (volatile uint32_t *)SPI_STATUS_ADDR;

static uint32_t spi_ctrl_shadow;

static void spi_wait_idle(void)
{
	while (*spi_status & SPI_STA_BUSY)
		;
}

void write_leds(uint8_t value)
{
	*led_reg = value;
}

void spi_init(uint8_t clk_div)
{
	spi_ctrl_shadow = (uint32_t)clk_div | (1u << 11) | (1u << 12);
	*spi_ctrl = spi_ctrl_shadow;
}

void spi_oled_reset_pulse(void)
{
	spi_ctrl_shadow &= ~(1u << 11);
	*spi_ctrl = spi_ctrl_shadow;
	for (volatile int i = 0; i < 8000; i++)
		;
	spi_ctrl_shadow |= (1u << 11);
	*spi_ctrl = spi_ctrl_shadow;
}

void spi_set_dc_command(void)
{
	spi_ctrl_shadow &= ~(1u << 10);
	*spi_ctrl = spi_ctrl_shadow;
}

void spi_set_dc_data(void)
{
	spi_ctrl_shadow |= (1u << 10);
	*spi_ctrl = spi_ctrl_shadow;
}

void spi_write_byte(uint8_t b, int keep_cs_after)
{
	spi_wait_idle();
	*spi_tx = b;
	if (keep_cs_after)
		spi_ctrl_shadow |= (1u << 9);
	else
		spi_ctrl_shadow &= ~(1u << 9);
	*spi_ctrl = spi_ctrl_shadow | (1u << 8);
	spi_wait_idle();
}
