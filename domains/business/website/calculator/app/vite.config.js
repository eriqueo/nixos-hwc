import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { resolve } from 'path'

const siteDir = process.env.HWC_WEBSITE_SITE_DIR
if (!siteDir) throw new Error('HWC_WEBSITE_SITE_DIR is required')

export default defineConfig({
  resolve: { alias: { '@site-data': resolve(siteDir, 'src/_data') } },
  plugins: [react()],
  // Allow Vite's dev server to read the canonical JSON data files
  // that live in the website repo two levels up.
  server: {
    fs: {
      // Allow access to ../../site_files (the 11ty repo) for JSON imports.
      allow: [
        resolve(__dirname),
        resolve(siteDir),
      ],
    },
  },
  build: {
    // Output directly to the 11ty site source — no manual copy needed.
    outDir: resolve(siteDir, 'src/js'),
    emptyOutDir: false, // Don't wipe the directory (main.js etc live there).
    rollupOptions: {
      output: {
        entryFileNames: 'calculator.bundle.js',
        chunkFileNames: 'calculator-[name].js',
        assetFileNames: 'calculator.[ext]',
      },
    },
  },
})
