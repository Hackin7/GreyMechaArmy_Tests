import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'
import { resolve } from 'node:path'

// https://vite.dev/config/
export default defineConfig({
  plugins: [svelte()],
  base: './', // Use relative paths for GitHub Pages
  build: {
    rollupOptions: {
      input: {
        app: resolve(process.cwd(), 'index.html'),
      },
    },
  },
})
