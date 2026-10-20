import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests/browser',
  timeout: 120000,
  expect: { timeout: 30000 },
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: { baseURL: 'http://127.0.0.1:4188/GreyMechaArmy_Tests/', viewport: { width: 1440, height: 1100 }, screenshot: 'only-on-failure', trace: 'retain-on-failure' },
  webServer: { command: 'node tests/serve.mjs', url: 'http://127.0.0.1:4188/GreyMechaArmy_Tests/', reuseExistingServer: !process.env.CI, timeout: 30000 }
});
