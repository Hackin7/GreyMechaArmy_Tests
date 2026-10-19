import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';

const memory=[];let address=0;
for(const token of (await readFile(new URL('../../src/lib/presets/oled-fast/stonks.mem',import.meta.url),'utf8')).trim().split(/\s+/)) {
  if(token.startsWith('@')) address=parseInt(token.slice(1),16);else memory[address++]=parseInt(token,16);
}
const color=value=>[Math.round(((value>>11)&31)*255/31),Math.round(((value>>5)&63)*255/63),Math.round((value&31)*255/31),255];
const imageCenter=color(memory[32*96+48]);
function referenceHash(mode=0) {
  let hash=2166136261;
  for(let y=0;y<240;y++) for(let x=0;x<240;x++) {
    const value=mode===1 ? (y<40||y>=200?0:memory[Math.floor((y-40)*2/5)*96+Math.floor(x*2/5)])
      :mode===2 ? (x<24||x>=216||y<56||y>=184?0:memory[Math.floor((y-56)/2)*96+Math.floor((x-24)/2)])
      :memory[Math.floor(y*4/15)*96+Math.floor(x*2/5)];
    for(const byte of color(value)) hash=Math.imul(hash^byte,16777619)>>>0;
  }
  return hash;
}
const imageHashes=[0,1,2].map(referenceHash);
async function canvasHash(page) {
  return page.getByTestId('oled-display').evaluate(canvas=>{
    let hash=2166136261;
    for(const byte of canvas.getContext('2d').getImageData(0,0,240,240).data) hash=Math.imul(hash^byte,16777619)>>>0;
    return hash;
  });
}

async function editTop(page, source) {
  await page.getByRole('button', { name: 'top.v', exact: true }).click();
  const editor = page.locator('.cm-content');
  await editor.click(); await editor.press('ControlOrMeta+A'); await page.keyboard.insertText(source);
}
async function openSimulator(page) { await page.getByRole('button', { name: 'Simulator', exact: true }).click(); }
async function compile(page) {
  await page.getByRole('button', { name: 'Compile & Run', exact: true }).click();
  await expect(page.getByTestId('sim-status')).toHaveText('running', { timeout: 90000 });
}
async function loadPreset(page, name) {
  await page.getByRole('button', { name: 'Other', exact: true }).click();
  await page.getByRole('button', { name, exact: true }).click();
  await openSimulator(page);
}
async function pause(page) { await page.getByRole('button', { name: 'Pause', exact: true }).click(); await expect(page.getByTestId('sim-status')).toHaveText('paused'); }
async function pixel(page, x = 120, y = 120) {
  return page.getByTestId('oled-display').evaluate((canvas, { x, y }) => [...canvas.getContext('2d').getImageData(x, y, 1, 1).data], { x, y });
}

test('production worker: buttons, keyboard, pause, stepping, stale source, errors and cancellation', async ({ page }, testInfo) => {
  const errors = []; page.on('pageerror', error => errors.push(error.message));
  await page.goto('./');
  await openSimulator(page);await compile(page);await pause(page);
  await expect(page.getByTestId('sim-cycles')).not.toHaveText('0');
  await editTop(page, "module top(input [6:0] btn,input [7:0] pmod_j1,output [7:0] led); assign led={pmod_j1[0],~btn}; endmodule");
  await openSimulator(page); await compile(page); await pause(page);
  await expect(page.getByTestId('led-7')).toHaveAttribute('data-value','1');
  await page.getByRole('button',{name:'PMOD J1[0]: high',exact:true}).click();
  await expect(page.getByTestId('led-7')).toHaveAttribute('data-value','0');
  await page.getByRole('button',{name:'PMOD J1[0]: reset low',exact:true}).click();
  const panel = page.getByRole('region', { name: 'GreyMecha simulator keyboard controls' });
  await panel.focus(); await page.keyboard.down('1'); await page.keyboard.down('2');
  await expect(page.getByTestId('led-0')).toHaveAttribute('data-value', '1');
  await expect(page.getByTestId('led-1')).toHaveAttribute('data-value', '1');
  await page.keyboard.up('1'); await page.keyboard.up('2');
  await expect(page.getByTestId('led-0')).toHaveAttribute('data-value', '0');
  await page.keyboard.down('7'); await expect(page.getByTestId('led-6')).toHaveAttribute('data-value', '1');
  await page.locator('.cm-content').click();
  await expect(page.getByTestId('led-6')).toHaveAttribute('data-value', '0'); await page.keyboard.up('7');
  const button = page.getByRole('button', { name: 'BTN 3', exact: true });
  await button.hover(); await page.mouse.down(); await expect(page.getByTestId('led-3')).toHaveAttribute('data-value', '1');
  await page.keyboard.down('4');await page.mouse.up();
  await expect(page.getByTestId('led-3')).toHaveAttribute('data-value','1');
  await page.keyboard.up('4');await expect(page.getByTestId('led-3')).toHaveAttribute('data-value', '0');
  const cycles = await page.getByTestId('sim-cycles').innerText();
  await page.getByRole('button', { name: 'Step Cycle', exact: true }).click();
  await expect(page.getByTestId('sim-cycles')).not.toHaveText(cycles);
  await page.getByRole('button', { name: 'Restart', exact: true }).click();
  await expect(page.getByTestId('sim-cycles')).toHaveText('0');
  await page.screenshot({ path: testInfo.outputPath('board-controls.png'), fullPage: true });
  await editTop(page, 'module top(input [6:0] btn,output [7:0] led); assign led = ; endmodule');
  await expect(page.getByTestId('sim-status')).toHaveText('outdated');
  await page.getByRole('button', { name: 'Compile & Run', exact: true }).click();
  await expect(page.getByRole('alert')).toContainText('failed');
  await editTop(page, "module top(input [4:0] btn,output [7:0] led); assign led={3'b0,~btn}; endmodule");
  await page.getByRole('button', { name: 'Compile & Run', exact: true }).click();
  await page.getByRole('button', { name: 'Stop', exact: true }).click();
  await expect(page.getByTestId('sim-status')).toHaveText('stopped');
  await compile(page); await expect(page.getByRole('button', { name: 'BTN 6', exact: true })).toBeDisabled();
  expect(errors).toEqual([]);
});

test('both unmodified OLED presets render in Pixel Preview', async ({ page }, testInfo) => {
  await page.goto('./'); await loadPreset(page, 'Load OLED'); await compile(page);
  await expect.poll(async () => Number(await page.getByTestId('sim-frames').innerText()), { timeout: 90000 }).toBeGreaterThan(0);
  await pause(page); expect(await pixel(page)).toEqual([0,125,0,255]);
  await page.screenshot({ path: testInfo.outputPath('simple-pixel-preview.png'), fullPage: true });
  await loadPreset(page, 'Load OLED (Advanced)'); await compile(page);
  await expect.poll(async () => Number(await page.getByTestId('sim-frames').innerText()), { timeout: 90000 }).toBeGreaterThan(0);
  await pause(page); expect(await pixel(page)).toEqual([255,255,255,255]);
  await page.getByRole('button', { name: 'Resume', exact: true }).click();
  const panel = page.getByRole('region', { name: 'GreyMecha simulator keyboard controls' });
  await panel.focus(); await page.keyboard.down('2');
  await expect.poll(() => pixel(page), { timeout: 90000 }).toEqual([255,0,0,255]);
  await page.keyboard.up('2'); await page.keyboard.down('1');
  await expect.poll(() => pixel(page), { timeout: 90000 }).toEqual(imageCenter);
  await expect.poll(() => canvasHash(page), {timeout:90000}).toEqual(imageHashes[0]);
  await pause(page);
  await page.screenshot({ path: testInfo.outputPath('advanced-pixel-preview.png'), fullPage: true });
  await page.keyboard.up('1');
});

test('advanced OLED SPI: image, color buttons, aspect modes and reset', async ({ page }, testInfo) => {
  test.setTimeout(600000);
  await page.goto('./');await loadPreset(page,'Load OLED (Advanced)');
  await page.getByLabel('OLED rendering',{exact:true}).selectOption('spi');await compile(page);
  await expect.poll(async()=>Number(await page.getByTestId('sim-frames').innerText()),{timeout:480000}).toBeGreaterThan(0);
  expect(await pixel(page)).toEqual([255,255,255,255]);
  const panel=page.getByRole('region',{name:'GreyMecha simulator keyboard controls'});
  await panel.focus();await page.keyboard.down('2');
  await expect.poll(()=>pixel(page),{timeout:90000}).toEqual([255,0,0,255]);
  await page.keyboard.up('2');await page.keyboard.down('1');
  await expect.poll(()=>pixel(page),{timeout:90000}).toEqual(imageCenter);
  await expect.poll(()=>canvasHash(page),{timeout:90000}).toEqual(imageHashes[0]);
  await page.keyboard.down('6');
  await expect(page.getByTestId('led-0')).toHaveAttribute('data-value','1',{timeout:90000});
  await page.keyboard.up('6');
  await expect.poll(()=>pixel(page,120,10),{timeout:90000}).toEqual([0,0,0,255]);
  await expect.poll(()=>canvasHash(page),{timeout:90000}).toEqual(imageHashes[1]);
  await page.keyboard.down('6');
  await expect(page.getByTestId('led-1')).toHaveAttribute('data-value','1',{timeout:90000});
  await page.keyboard.up('6');
  await expect.poll(()=>canvasHash(page),{timeout:90000}).toEqual(imageHashes[2]);
  await pause(page);
  await page.screenshot({path:testInfo.outputPath('advanced-spi-image.png'),fullPage:true});
  await page.keyboard.up('1');await page.getByRole('button',{name:'Resume',exact:true}).click();
  await panel.focus();await page.keyboard.down('7');
  await expect(page.getByTestId('led-7')).toHaveAttribute('data-value','0');
  await expect.poll(()=>pixel(page),{timeout:30000}).toEqual([0,0,0,255]);
  await page.keyboard.up('7');
});

test('simple OLED renders through original SPI driver and changing mode recompiles', async ({ page }, testInfo) => {
  test.setTimeout(600000);
  await page.goto('./'); await loadPreset(page, 'Load OLED');
  await page.getByLabel('OLED rendering', { exact: true }).selectOption('spi'); await compile(page);
  await expect.poll(async () => Number(await page.getByTestId('sim-frames').innerText()), { timeout: 480000 }).toBeGreaterThan(0);
  await pause(page); expect(await pixel(page)).toEqual([0,125,0,255]);
  await page.screenshot({ path: testInfo.outputPath('simple-spi.png'), fullPage: true });
  await page.getByLabel('OLED rendering', { exact: true }).selectOption('pixel');
  await expect(page.getByTestId('sim-status')).toHaveText('running', { timeout: 90000 });
  await expect.poll(() => pixel(page), { timeout: 90000 }).toEqual([0,125,0,255]);
});
