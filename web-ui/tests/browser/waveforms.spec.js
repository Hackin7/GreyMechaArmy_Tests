import { test, expect } from '@playwright/test';

async function editTop(page, source) {
  await page.getByRole('button', { name: 'top.v', exact: true }).click();
  const editor = page.locator('.cm-content'); await editor.click(); await editor.press('ControlOrMeta+A'); await page.keyboard.insertText(source);
}
async function compile(page) {
  await page.getByRole('button', { name: 'Compile & Run', exact: true }).click();
  await expect(page.getByTestId('sim-status')).toHaveText('running', { timeout: 90000 });
}
async function pause(page) {
  await page.getByRole('button', { name: 'Pause', exact: true }).click();
  await expect(page.getByTestId('sim-status')).toHaveText('paused');
}
const source = `module top(input clk_ext,input [6:0] btn,output [7:0] led);
reg [63:0] counter=64'hfedcba9876543200;
always @(posedge clk_ext) counter<=counter+1;
assign led=counter[7:0]^counter[63:56]^{1'b0,~btn}; endmodule`;

test('waveforms: capture, internal/wide buses, cursor, navigation, resize, rollover and lifecycle', async ({ page }, testInfo) => {
  const errors = []; page.on('pageerror', error => errors.push(error.message));
  await page.goto('./'); await editTop(page, source);
  await page.getByRole('button', { name: 'Simulator', exact: true }).click();
  const toggle = page.getByRole('button', { name: /Waveforms/, exact: false });
  await expect(toggle).toHaveAttribute('aria-expanded', 'false');
  await compile(page); await pause(page);
  await toggle.click();
  await expect(page.getByTestId('waveform-value').filter({ hasText: /^btn:/ })).toHaveText('btn: 0x7F');
  await expect(page.getByTestId('waveform-history')).toContainText('1/8192');
  const boardButton = page.getByRole('button', { name: 'BTN 0', exact: true });
  await boardButton.hover(); await page.mouse.down();
  await expect(page.getByTestId('waveform-value').filter({ hasText: /^btn:/ })).toHaveText('btn: 0x7E');
  await page.mouse.up();
  await expect(page.getByTestId('waveform-value').filter({ hasText: /^btn:/ })).toHaveText('btn: 0x7F');
  await expect(page.getByTestId('waveform-history')).toContainText('3/8192');
  await page.getByRole('button', { name: 'Previous waveform transition', exact: true }).click();
  await expect(page.getByTestId('waveform-value').filter({ hasText: /^btn:/ })).toHaveText('btn: 0x7E');
  await page.getByRole('button', { name: 'Next waveform transition', exact: true }).click();
  await expect(page.getByTestId('waveform-value').filter({ hasText: /^btn:/ })).toHaveText('btn: 0x7F');

  await page.getByRole('button', { name: /Signals \(/ }).click();
  await page.getByRole('textbox', { name: 'Search waveform signals' }).fill('counter');
  const counter = page.getByRole('checkbox', { name: /counter.*64 bits/ }).first();
  await expect(counter).toBeVisible(); await counter.check();
  await page.getByRole('textbox', { name: 'Search waveform signals' }).fill('gm_ext');
  await page.getByRole('checkbox', { name: /gm_ext/ }).check();
  await page.getByRole('button', { name: /Signals \(/ }).click();
  await expect(page.getByTestId('waveform-history')).toContainText('1/8192');
  await page.getByRole('button', { name: 'Step Cycle', exact: true }).click();
  await expect(page.getByTestId('waveform-history')).not.toContainText('1/8192');
  await expect(page.getByTestId('waveform-value').filter({ hasText: /counter/ })).toContainText('0xFEDCBA9876');
  await page.getByRole('combobox', { name: 'Waveform number format' }).selectOption('10');
  await expect(page.getByTestId('waveform-value').filter({ hasText: /^btn:/ })).toHaveText('btn: 127');
  await page.getByRole('combobox', { name: 'Waveform number format' }).selectOption('16');
  await page.getByRole('button', { name: 'Fit History', exact: true }).click();
  await page.getByRole('button', { name: 'Zoom waveform in', exact: true }).click();
  await page.getByRole('button', { name: 'Zoom waveform out', exact: true }).click();
  await page.getByRole('button', { name: 'Pan waveforms left', exact: true }).click();
  await page.getByRole('button', { name: 'Pan waveforms right', exact: true }).click();
  const canvas = page.getByTestId('waveform-canvas'); await canvas.focus(); await page.keyboard.press('ArrowLeft');
  await expect(page.getByTestId('waveform-cursor')).toContainText('event');
  const resize = page.getByRole('separator', { name: 'Resize waveforms', exact: true });
  await resize.focus(); await page.keyboard.press('ArrowUp'); await expect(resize).toHaveAttribute('aria-valuenow', '340');
  const handle = await resize.boundingBox(); await page.mouse.move(handle.x + handle.width / 2, handle.y + 3); await page.mouse.down(); await page.mouse.move(handle.x + handle.width / 2, handle.y - 37); await page.mouse.up();
  await expect(resize).toHaveAttribute('aria-valuenow', '380');
  await page.getByRole('button', { name: 'Follow Latest', exact: true }).click();
  await page.getByRole('button', { name: 'Resume', exact: true }).click();
  await expect(page.getByTestId('waveform-history')).toContainText('earlier records discarded');
  await pause(page);
  await page.getByRole('button', { name: 'Fit History', exact: true }).click();
  for (let i = 0; i < 8; i++) await page.getByRole('button', { name: 'Zoom waveform in', exact: true }).click();
  await page.screenshot({ path: testInfo.outputPath('waveforms-desktop.png'), fullPage: true });
  await page.getByRole('button', { name: 'Clear Capture', exact: true }).click();
  await expect(page.getByTestId('waveform-history')).toContainText('1/8192');
  await page.getByRole('button', { name: 'Restart', exact: true }).click();
  await expect(page.getByTestId('sim-cycles')).toHaveText('0');
  await expect(page.getByTestId('waveform-history')).toContainText('1/8192');
  await expect(page.getByTestId('waveform-value').filter({ hasText: /counter/ })).toContainText('0xFEDCBA9876543200');
  await toggle.click(); await page.getByRole('button', { name: 'Step Cycle', exact: true }).click(); await toggle.click();
  await expect(page.getByTestId('waveform-history')).toContainText('1/8192');
  await editTop(page, 'module top(output [7:0] led); assign led=8; endmodule');
  await expect(page.getByTestId('sim-status')).toHaveText('outdated');
  await expect(page.getByTestId('waveform-history')).toContainText('0/8192');
  await expect(page.getByRole('button', { name: 'Clear Capture', exact: true })).toBeDisabled();
  await compile(page); await expect(page.getByTestId('waveform-value').filter({ hasText: /^led:/ })).toHaveText('led: 0x08');
  expect(errors).toEqual([]);
});

test('waveforms: narrow layout and both OLED rendering modes', async ({ page }, testInfo) => {
  const errors = []; page.on('pageerror', error => errors.push(error.message));
  await page.goto('./');
  await page.getByRole('button', { name: 'Other', exact: true }).click();
  await page.getByRole('button', { name: 'Load OLED', exact: true }).click();
  await page.getByRole('button', { name: 'Simulator', exact: true }).click();
  await page.getByRole('button', { name: /Waveforms/ }).click();
  await compile(page);
  await expect.poll(async () => Number(await page.getByTestId('sim-frames').innerText()), { timeout: 90000 }).toBeGreaterThan(0);
  await pause(page);
  await expect(page.getByTestId('waveform-value')).toHaveCount(2);
  await page.getByRole('button', { name: 'Fit History', exact: true }).click();
  await page.screenshot({ path: testInfo.outputPath('waveforms-oled-pixel.png'), fullPage: true });
  await page.getByRole('combobox', { name: 'OLED rendering', exact: true }).selectOption('spi');
  await expect(page.getByTestId('sim-status')).toHaveText('running', { timeout: 90000 });
  await expect.poll(async () => Number(await page.getByTestId('sim-frames').innerText()), { timeout: 90000 }).toBeGreaterThan(0);
  await pause(page);
  await page.setViewportSize({ width: 760, height: 1100 });
  await page.getByTestId('waveform-body').scrollIntoViewIfNeeded();
  await expect(page.getByTestId('waveform-canvas')).toBeVisible();
  const panel = page.getByRole('region', { name: 'Simulation waveforms', exact: true });
  expect(await panel.evaluate(node => node.scrollWidth <= node.clientWidth + 1)).toBeTruthy();
  await page.screenshot({ path: testInfo.outputPath('waveforms-narrow-spi.png'), fullPage: true });
  expect(errors).toEqual([]);
});
