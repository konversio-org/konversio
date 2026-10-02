import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Both @chatwoot/ninja-keys and @material/mwc-icon depend on lit@2.2.6.
// pnpm stores a single copy but Vite's dev server serves each symlink path
// as a separate module, triggering Lit's "Multiple versions" console warning.
// Aliasing forces all 'lit' imports to a single canonical path.
// The version is pinned in pnpm-lock.yaml; update if a renovate/dependabot
// PR bumps lit or ninja-keys.
const litPath = path.resolve(
  __dirname,
  'node_modules/.pnpm/lit@2.2.6/node_modules/lit'
);

export const aliases = {
  lit: litPath,
  vue: 'vue/dist/vue.esm-bundler.js',
  components: path.resolve('./app/javascript/dashboard/components'),
  next: path.resolve('./app/javascript/dashboard/components-next'),
  v3: path.resolve('./app/javascript/v3'),
  dashboard: path.resolve('./app/javascript/dashboard'),
  helpers: path.resolve('./app/javascript/shared/helpers'),
  shared: path.resolve('./app/javascript/shared'),
  survey: path.resolve('./app/javascript/survey'),
  widget: path.resolve('./app/javascript/widget'),
  assets: path.resolve('./app/javascript/dashboard/assets'),
};

export const vueOptions = {
  template: {
    compilerOptions: {
      isCustomElement: tag => ['ninja-keys'].includes(tag),
    },
  },
};
