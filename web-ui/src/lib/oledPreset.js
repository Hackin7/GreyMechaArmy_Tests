import top from './presets/oled-fast/top.v?raw';
import spi from './presets/oled-fast/simple_spi_master.v?raw';
import debounce from './presets/oled-fast/btn_debounce.v?raw';
import pll from './presets/oled-fast/ecp5_oled_pll.v?raw';
import init from './presets/oled-fast/oled_init.v?raw';
import stream from './presets/oled-fast/oled_stream.v?raw';
import display from './presets/oled-fast/oled_gc9a01.v?raw';
import stretch from './presets/oled-fast/image_stretch.v?raw';
import rom from './presets/oled-fast/gc9a01_init_rom.vh?raw';
import image from './presets/oled-fast/stonks.mem?raw';
import pinout from './presets/oled-fast/pinout.lpf?raw';
import simpleTop from './presets/oled-simple/top.v?raw';

export const oledDriverModules = {
  'simple_spi_master.v': spi,
  'ecp5_oled_pll.v': pll,
  'oled_init.v': init,
  'oled_stream.v': stream,
  'oled_gc9a01.v': display,
  'gc9a01_init_rom.vh': rom
};

export const oledModules = {
  ...oledDriverModules,
  'btn_debounce.v': debounce,
  'image_stretch.v': stretch
};

export const oledSimple = {
  'top.v': simpleTop,
  ...oledDriverModules,
  'pinout.lpf': pinout
};

export const oledDemo = {
  'top.v': top,
  ...oledModules,
  'stonks.mem': image,
  'pinout.lpf': pinout
};
