import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { resolve } from 'path'

export default defineConfig({
  plugins: [react()],
  // Allow Vite's dev server to read the canonical JSON data files
  // that live in the website repo two levels up.
  server: {
    fs: {
      // Allow access to ../../site_files (the 11ty repo) for JSON imports.
      allow: [
        resolve(__dirname),
        resolve(__dirname, '../../site_files'),
      ],
    },
  },
  build: {
    // Output directly to the 11ty site source — no manual copy needed.
    outDir: resolve(__dirname, '../../site_files/src/js'),
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
