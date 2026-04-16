/*
 * Declarative CPU / system clock for busy-wait timing. Must match the real
 * picorv32 clock in src/top.v (OSCG DIV, optional USE_SYS_PLL).
 *
 * Tune if gc9a01_delay_ms() runs fast or slow:
 * - Set BOARD_CPU_HZ to measured f_sys (scope, nextpnr timing, or clock spec).
 * - Adjust GC9A01_DELAY_INNER_CYCLES if needed (inner-loop cycles per iter at -Os).
 */
#ifndef BOARD_CLOCK_H
#define BOARD_CLOCK_H

#include <stdint.h>

#ifndef BOARD_CPU_HZ
/* Default: OSCG DIV=5 ~62 MHz vs prior DIV=3 ~103 MHz (see top.v comment). Override with -DBOARD_CPU_HZ=... */
#define BOARD_CPU_HZ 62000000u
#endif

/*
 * Approximate RISC-V cycles per inner `for` iteration in gc9a01_delay_ms (increment +
 * compare + branch). Typical range 2–5 for -Os; raise this if delays run long.
 */
#ifndef GC9A01_DELAY_INNER_CYCLES
#define GC9A01_DELAY_INNER_CYCLES 3u
#endif

#define GC9A01_DELAY_INNER_LOOPS_PER_MS \
	((BOARD_CPU_HZ / 1000u) / GC9A01_DELAY_INNER_CYCLES)

#endif
