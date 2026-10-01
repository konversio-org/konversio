## Capability: sdk-bundle-size-reduction

The customer-facing JavaScript SDK — the artifact loaded on every page of every customer's website — gets a dedicated build pipeline and a slimmer runtime, ported from upstream v4.17.1 (MIT; verbatim porting legal). This replaces the v4.13.0-era `BUILD_MODE=library` env-var branch inside the main Vite config.

---

## ADDED Requirements

### Requirement: Dedicated SDK build pipeline

The SDK SHALL be built by its own Vite config (`vite.lib.config.ts`) as a single-file IIFE bundle (`inlineDynamicImports: true`) written to `public/packs/js/sdk.js`, with shared resolve aliases and Vue options extracted into `vite.shared.ts` consumed by both configs. The main config (Konversio's `vite.config.mts`) SHALL no longer contain a `BUILD_MODE=library` branch.

#### Scenario: build:sdk produces the single-file bundle

- Given the new pipeline
- When `pnpm run build:sdk` runs
- Then `public/packs/js/sdk.js` is produced as a self-contained IIFE with no dynamic-import chunks

#### Scenario: main build excludes library mode

- Given the slimmed `vite.config.mts`
- When the regular app build runs
- Then no `BUILD_MODE` environment variable is consulted and the SDK is not part of the multi-entrypoint build

#### Scenario: precompile builds the SDK automatically

- Given `lib/tasks/build.rake` enhances `assets:precompile` with a `before_assets_precompile` step
- When `bundle exec rails assets:precompile` runs in a clean checkout
- Then `pnpm run build:sdk` executes and the SDK artifacts land in `public/packs/js/`

---

### Requirement: Pre-compressed SDK assets

The SDK build SHALL emit `sdk.js.br` (brotli, maximum quality) and `sdk.js.gz` (gzip, best compression) alongside `sdk.js`, generated at build time via `node:zlib`, so static file servers can serve pre-compressed responses.

#### Scenario: compressed siblings emitted

- Given a successful `build:sdk` run
- When the output directory is inspected
- Then `js/sdk.js`, `js/sdk.js.br`, and `js/sdk.js.gz` all exist
- And the build fails loudly if the SDK chunk was not generated

---

### Requirement: Bundle analysis tooling

The repository SHALL provide `analyze:bundle:sdk` and `analyze:bundle:widget` scripts (via `rollup-plugin-visualizer` and dedicated analyze configs) so bundle size regressions can be inspected locally.

#### Scenario: analyzer runs against both bundles

- Given the analyze configs and devDependency are installed
- When `pnpm run analyze:bundle:sdk` or `pnpm run analyze:bundle:widget` runs
- Then a visualizer report for the respective bundle is produced

---

### Requirement: SDK runtime free of md5 and date-fns

The SDK bundle's dependency graph SHALL NOT include the `md5` package or `date-fns`: `computeHashForUserData` SHALL use a self-contained FNV-1a 128-bit hash (BigInt-based, 32-hex-character output), campaign snooze expiry SHALL use plain `Date` arithmetic, and the SDK stylesheet SHALL be inlined via a `sdk.css?inline` import (renaming the synthetic `sdk.js` to `sdk.css`). `md5` SHALL be removed from `package.json` dependencies.

#### Scenario: user-data hash is stable and dependency-free

- Given a widget visitor with identifier and user attributes
- When `computeHashForUserData` is computed twice for identical input
- Then both calls return the same 32-character hex string
- And the SDK bundle contains no `md5` module

#### Scenario: one-time cookie refresh after hash change

- Given a returning visitor whose `cw_user_*` cookie was written under the old md5-based hash
- When the new SDK loads
- Then the hash mismatch triggers a single contact data refresh and the cookie is rewritten under the new hash
- And no conversation data is lost in the process

#### Scenario: campaign snooze expiry unchanged in behavior

- Given a visitor snoozes a campaign
- When the snooze cookie is written
- Then its expiry is approximately one hour in the future, computed without `date-fns`

---

### Requirement: Measurable size reduction

The change SHALL produce a measurably smaller SDK bundle than the previous `BUILD_MODE=library` build, with the delta recorded in the PR description.

#### Scenario: size delta documented

- Given the SDK built before and after this change
- When the PR is opened
- Then the description states the old and new bundle sizes (raw and compressed)
- And the new bundle is smaller

#### Scenario: needs investigation — contact refresh scope

- Given upstream bundled a `getUserString` attribute expansion with the hash swap under a separate changelog line ("improved widget contact refreshes")
- When implementing the hash swap
- Then needs investigation: whether the attribute expansion is functionally required here or belongs to a follow-up change; the outcome SHALL be recorded in the PR
