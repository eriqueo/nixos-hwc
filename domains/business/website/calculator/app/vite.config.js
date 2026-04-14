import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { resolve } from 'path'

export default defineConfig({
  plugins: [react()],
  build: {
    // Output directly to the 11ty site source — no manual copy needed
    outDir: resolve(__dirname, '../../site_files/src/js'),
    emptyOutDir: false, // Don't wipe the directory (main.js and tracking.js live there)
    rollupOptions: {
      output: {
        entryFileNames: 'calculator.bundle.js',
        chunkFileNames: 'calculator-[name].js',
        assetFileNames: 'calculator.[ext]'
      }
    }
  }
})
