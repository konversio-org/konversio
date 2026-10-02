/// <reference types="vitest" />
process.env.TZ = 'UTC';

import { defineConfig } from 'vite';
import ruby from 'vite-plugin-ruby';
import vue from '@vitejs/plugin-vue';
import yaml from '@rollup/plugin-yaml';
import { aliases, vueOptions } from './config/vite/shared';

const isTestMode = process.env.TEST === 'true';

const plugins = isTestMode
  ? [vue(vueOptions), yaml()]
  : [ruby(), vue(vueOptions), yaml()];

export default defineConfig({
  plugins: plugins,
  css: {
    preprocessorOptions: {
      // Opt into Sass's modern compiler API. The legacy JS API was
      // deprecated in Dart Sass 1.79 and will be removed in 2.0.0;
      // switching now silences the per-file warning and keeps the build
      // forward-compatible. Same sass package, just a newer entrypoint.
      scss: { api: 'modern' },
    },
  },
  server: {
    // Vite 5 default-denies requests whose Host header isn't on this
    // allowlist. Inside docker compose, Rails proxies to http://vite:3036
    // so the Host header reaches Vite as "vite". Localhost is the host
    // header when the browser hits Vite directly on the published port.
    allowedHosts: ['vite', 'localhost'],
    watch: {
      usePolling: true,
      interval: 1000,
    },
  },
  resolve: { alias: aliases },
  test: {
    environment: 'jsdom',
    include: ['app/**/*.{test,spec}.?(c|m)[jt]s?(x)'],
    coverage: {
      reporter: ['lcov', 'text'],
      include: ['app/**/*.js', 'app/**/*.vue'],
      exclude: [
        'app/**/*.@(spec|stories|routes).js',
        '**/specs/**/*',
        '**/i18n/**/*',
      ],
    },
    globals: true,
    outputFile: 'coverage/sonar-report.xml',
    pool: 'threads',
    poolOptions: {
      threads: {
        singleThread: false,
      },
    },
    server: {
      deps: {
        inline: ['tinykeys', '@material/mwc-icon'],
      },
    },
    setupFiles: ['fake-indexeddb/auto', 'config/test/setup.js'],
    mockReset: true,
    clearMocks: true,
  },
});
