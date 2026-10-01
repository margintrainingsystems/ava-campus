import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: { port: 5174, strictPort: true },
  build: {
    sourcemap: false,
    target: 'es2022',
    rolldownOptions: {
      output: {
        // Las librerías van en archivos aparte: cambian poco y el navegador las guarda en caché.
        codeSplitting: {
          groups: [
            { name: 'supabase', test: /node_modules[\\/]@supabase[\\/]/ },
            { name: 'react', test: /node_modules[\\/](react|react-dom|react-router|react-router-dom|scheduler)[\\/]/ },
          ],
        },
      },
    },
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
    css: false,
    env: {
      VITE_SUPABASE_URL: 'https://ejemplo.supabase.co',
      VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_prueba',
    },
  },
})
