import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['icon-192.png', 'icon-512.png'],
      manifest: false, // we use our own public/manifest.json
      workbox: {
        // Only precache the app shell — NOT data JSON files
        globPatterns: ['**/*.{js,css,html,ico,png,svg}'],
        // Never cache sw.js itself
        dontCacheBustURLsMatching: /assets\//,
        cleanupOutdatedCaches: true,
        // Force new SW to take over immediately
        skipWaiting: true,
        clientsClaim: true,
        runtimeCaching: [
          {
            urlPattern: /^https:\/\/fonts\.googleapis\.com\/.*/i,
            handler: 'CacheFirst',
          },
        ],
      },
    }),
  ],
  build: {
    outDir: 'dist',
    sourcemap: false,
  },
  server: {
    port: 5173,
    host: true,
  },
});
