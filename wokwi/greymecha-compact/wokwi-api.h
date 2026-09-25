#ifndef GREYMECHA_WOKWI_API_H
#define GREYMECHA_WOKWI_API_H
#include <stdbool.h>
#include <stdint.h>
enum pin_value { LOW = 0, HIGH = 1 };
enum pin_mode { INPUT = 0, OUTPUT = 1, OUTPUT_HIGH = 17 };
enum edge { RISING = 1, FALLING = 2, BOTH = 3 };
int __attribute__((export_name("__wokwi_api_version_1"))) __attribute__((weak)) __wokwi_api_version_1(void) { return 1; }
typedef int32_t pin_t;
typedef uint32_t buffer_t;
typedef uint32_t timer_t;
typedef struct { void *user_data; uint32_t edge; void (*pin_change)(void *, pin_t, uint32_t); } pin_watch_config_t;
typedef struct { void *user_data; void (*callback)(void *); uint32_t reserved[8]; } timer_config_t;
extern __attribute__((export_name("chipInit"))) void chip_init(void);
extern __attribute__((import_name("pinInit"))) pin_t pin_init(const char *, uint32_t);
extern __attribute__((import_name("pinRead"))) uint32_t pin_read(pin_t);
extern __attribute__((import_name("pinWrite"))) void pin_write(pin_t, uint32_t);
extern __attribute__((import_name("pinWatch"))) bool pin_watch(pin_t, pin_watch_config_t *);
extern __attribute__((import_name("attrInit"))) uint32_t attr_init(const char *, uint32_t);
extern __attribute__((import_name("attrRead"))) uint32_t attr_read(uint32_t);
extern __attribute__((import_name("timerInit"))) timer_t timer_init(const timer_config_t *);
extern __attribute__((import_name("timerStart"))) void timer_start(timer_t, uint32_t, bool);
extern __attribute__((import_name("framebufferInit"))) buffer_t framebuffer_init(uint32_t *, uint32_t *);
extern __attribute__((import_name("bufferWrite"))) void buffer_write(buffer_t, uint32_t, void *, uint32_t);
#endif
