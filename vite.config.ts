import { defineConfig } from 'vite';
export default defineConfig({ build: { rollupOptions: { input: { index: 'index.html', 'player-adapter': 'src/player/adapter.ts' }, output: { entryFileNames: '[name].js' } } } });
