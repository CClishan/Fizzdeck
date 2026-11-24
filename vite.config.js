import path from 'node:path';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  plugins: [react(), tailwindcss()],
  publicDir: false,
  resolve: { alias: { '@': path.resolve(import.meta.dirname, 'src') } },
  build: {
    outDir: 'public',
    emptyOutDir: true,
    chunkSizeWarningLimit: 1200,
    rollupOptions: {
      input: {
        main: path.resolve(import.meta.dirname, 'index.html'),
        landing: path.resolve(import.meta.dirname, 'landing.html'),
      },
    },
  },
  server: { proxy: { '/api': 'http://127.0.0.1:4770' } },
});
