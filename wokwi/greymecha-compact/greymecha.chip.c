#include "wokwi-api.h"

static const char *button_names[5] = { "BTN0_N", "BTN1_N", "BTN2_N", "BTN3_N", "BTN4_N" };
static const char *control_names[5] = { "button0", "button1", "button2", "button3", "button4" };
static const char *led_names[8] = { "LED0", "LED1", "LED2", "LED3", "LED4", "LED5", "LED6", "LED7" };
static pin_t buttons[5];
static pin_t leds[8];
static uint32_t controls[5];
static buffer_t display;
static uint32_t display_width;
static uint32_t display_height;

static void redraw(void) {
  uint8_t pixels[160 * 44 * 4];
  for (uint32_t y = 0; y < display_height; y++) {
    for (uint32_t x = 0; x < display_width; x++) {
      uint32_t pixel = (y * display_width + x) * 4;
      uint32_t index = x / 20;
      bool lit = index < 8 && pin_read(leds[index]) == HIGH;
      bool inside = (x % 20 >= 5 && x % 20 <= 14 && y >= 17 && y <= 26);
      pixels[pixel + 0] = inside && lit ? 255 : 34;
      pixels[pixel + 1] = inside && lit ? 48 : 38;
      pixels[pixel + 2] = inside && lit ? 48 : 44;
      pixels[pixel + 3] = 255;
    }
  }
  buffer_write(display, 0, pixels, display_width * display_height * 4);
}

static void led_changed(void *user_data, pin_t pin, uint32_t value) {
  (void)user_data;
  (void)pin;
  (void)value;
  redraw();
}

static void poll_buttons(void *user_data) {
  (void)user_data;
  for (uint32_t i = 0; i < 5; i++) {
    pin_write(buttons[i], attr_read(controls[i]) ? LOW : HIGH);
  }
}

void chip_init(void) {
  display = framebuffer_init(&display_width, &display_height);
  for (uint32_t i = 0; i < 5; i++) {
    buttons[i] = pin_init(button_names[i], OUTPUT_HIGH);
    controls[i] = attr_init(control_names[i], 0);
  }
  for (uint32_t i = 0; i < 8; i++) {
    leds[i] = pin_init(led_names[i], INPUT);
    pin_watch_config_t watch = { .user_data = 0, .edge = BOTH, .pin_change = led_changed };
    pin_watch(leds[i], &watch);
  }
  timer_config_t timer_config = { .user_data = 0, .callback = poll_buttons };
  timer_t timer = timer_init(&timer_config);
  timer_start(timer, 10000, true);
  poll_buttons(0);
  redraw();
}
