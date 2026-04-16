#ifndef GC9A01_H
#define GC9A01_H

#include <stdint.h>

/* Classic pink #FFC0CB in RGB565 */
#define GC9A01_RGB565_PINK  ((uint16_t)0xFE19u)
#define GC9A01_RGB565_RED   ((uint16_t)0x001Fu)
#define GC9A01_RGB565_GREEN ((uint16_t)0x07E0u)
#define GC9A01_RGB565_BLUE  ((uint16_t)0xF800u)

void gc9a01_init(void);
void gc9a01_fill_screen_rgb565(uint16_t rgb565);
/* Each pixel cycles RED -> GREEN -> BLUE along scan order (index % 3). */
void gc9a01_fill_screen_rgb565_per_pixel_rgb(void);
void gc9a01_delay_ms(uint32_t ms);

#endif
