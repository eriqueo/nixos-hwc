import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { resolve } from 'path'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'

const siteDir = process.env.HWC_WEBSITE_SITE_DIR
if (!siteDir) throw new Error('HWC_WEBSITE_SITE_DIR is required')
const contract = createRequire(import.meta.url)(resolve(siteDir, 'export-measurement.cjs'))(siteDir)
const measurementModule = '\0virtual:hwc-measurement'

export default defineConfig({
  resolve: { alias: { '@site-data': resolve(siteDir, 'src/_data') } },
  plugins: [react(), {
    name: 'website-owned-measurement',
    resolveId(id) { if (id === 'virtual:hwc-measurement') return measurementModule },
    load(id) {
      if (id !== measurementModule) return
      // Embedded pages already install this before GTM. Standalone consumers
      // get the same producer, never another event vocabulary or save policy.
      return 'window.HWC_MEASUREMENT_CONTRACT ||= ' + JSON.stringify(contract) + ';\n' +
        readFileSync(resolve(siteDir, 'src/js/measurement.js'), 'utf8')
    },
  }],
  // Allow Vite's dev server to read the canonical JSON data files
  // that live in the website repo two levels up.
  server: {
    fs: {
      // Allow access to ../../site_files (the 11ty repo) for JSON imports.
      allow: [
        resolve(__dirname),
        resolve(siteDir),
        resolve(__dirname, '../../../estimator/src'),
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
