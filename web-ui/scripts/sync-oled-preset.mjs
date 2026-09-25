import { mkdir, readFile, writeFile } from 'node:fs/promises';

const source = new URL('../../io/fpga_oled_fast/', import.meta.url);
const target = new URL('../src/lib/presets/oled-fast/', import.meta.url);
const rtl = [
  'simple_spi_master.v', 'btn_debounce.v', 'ecp5_oled_pll.v',
  'oled_init.v', 'oled_stream.v', 'oled_gc9a01.v',
  'image_stretch.v', 'top.v', 'gc9a01_init_rom.vh'
];
const files = [...rtl.map((name) => [`src/${name}`, name]), ['stonks.mem', 'stonks.mem'], ['pinout.lpf', 'pinout.lpf']];

await mkdir(target, { recursive: true });
for (const [from, to] of files) {
  await writeFile(new URL(to, target), await readFile(new URL(from, source)));
}
console.log(`Synced ${files.length} OLED preset files from io/fpga_oled_fast.`);
