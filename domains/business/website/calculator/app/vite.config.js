import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  build: {
    // Build as a single bundle for embedding
    rollupOptions: {
      output: {
        // Use consistent filenames (no hash) for easier embedding
        entryFileNames: 'calculator.js',
        chunkFileNames: 'calculator-[name].js',
        assetFileNames: 'calculator.[ext]'
      }
    }
  }
})
