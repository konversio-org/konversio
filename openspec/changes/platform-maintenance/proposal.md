## Why

Konversio forked Chatwoot at v4.13.0 and has since diverged on platform maintenance. Upstream shipped a Rails 7.2.3.1 upgrade (v4.17.0), security bumps for Puma, the OAuth dependency family, and the Vite toolchain (v4.14.2), three widget/dashboard language additions (Uzbek in v4.16.0, Slovenian in v4.17.0, Estonian widget translations in v4.18.0), and an SDK bundle size reduction (v4.17.1). Konversio has partially absorbed this work on its own track — it already ran its own Rails 7.2 migration (commits `855e076a3`, `2d9a55d35`, the `allow_other_host` redirect fixes, and the hairtrigger 1.3.1 bump `ea4da5f94` around 2026-06) — but the runtime now sits in an unverified middle state: Rails is at 7.2.3.1 while Puma (6.4.3), the oauth/oauth2/oauth-tty gems, and the vite_rails/vite_ruby gems still lag upstream's patched versions, and the v4.13.0-era SDK build pipeline is untouched.

The locale gap is a registration gap as much as a content gap: Slovenian and Estonian translation files already exist on disk in Konversio (inherited from v4.13.0) but are not wired into the i18n registries, and Uzbek is absent entirely.

All items in this change track MIT-licensed upstream work; direct code-level reference and verbatim porting are legal.

## What Changes

- **Reconcile and verify the Rails 7.2.3.1 runtime** — confirm Konversio's own Rails 7.2 migration is complete and correct against upstream's v4.17.0 end state (Gemfile pin strategy, `db/schema.rb` version stamp, boot/spec health), and close remaining deltas from upstream's upgrade stack (`rails-i18n`, `devise-secure_password` source, sidekiq/jwt constraints) where they matter for us.
- **Apply the v4.14.2 dependency security updates** — bump Puma 6.4.3 → 7.2.x, oauth 1.1.0 → 1.1.6, oauth-tty 1.0.5 → 1.0.8, oauth2 2.0.9 → 2.0.22, and vite_rails/vite_ruby to the 3.10 line, matching upstream's patched versions.
- **Enable Uzbek, Slovenian, and Estonian translations** — add Uzbek locale files across the Rails backend, dashboard, widget, and survey apps; register Uzbek and Slovenian as selectable account locales in `LANGUAGES_CONFIG`; wire Slovenian and Estonian (already on disk) plus Uzbek into the widget, dashboard, and survey i18n registries.
- **Reduce the JavaScript SDK bundle size** — port upstream's dedicated SDK build pipeline (`vite.lib.config.ts`, single-IIFE output with pre-compressed `.br`/`.gz` assets, bundle-analysis configs), and slim the SDK runtime by dropping the `md5` and `date-fns/addHours` dependencies and inlining the SDK CSS via `?inline`.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `rails-7-2-runtime-reconcile`: Verification and reconciliation of Konversio's independently-executed Rails 7.2.3.1 migration against upstream's v4.17.0 upgrade stack.
- `dependency-security-updates`: Puma, OAuth-family, and Vite-toolchain dependency bumps matching upstream's v4.14.2 security posture.
- `widget-and-dashboard-locales`: Uzbek as a new full-stack language; Slovenian and Estonian registered/enabled from existing on-disk translations.
- `sdk-bundle-size-reduction`: Dedicated SDK build pipeline and removal of heavy SDK runtime dependencies.

## Impact

- `Gemfile` / `Gemfile.lock` — version pins and bumps for rails, puma, oauth/oauth2/oauth-tty (transitive), vite_rails/vite_ruby, rails-i18n, devise-secure_password, sidekiq, jwt.
- `db/schema.rb` — version stamp verification (`[7.2]`), no new migrations.
- `config/initializers/languages.rb` — two new `LANGUAGES_CONFIG` entries (Uzbek, Slovenian); `Account.locale` enum derives from it.
- `config/locales/uz.yml` (new), `app/javascript/dashboard/i18n/locale/uz/` (new, ~48 files), `app/javascript/widget/i18n/locale/uz.json` (new), `app/javascript/survey/i18n/locale/uz.json` (new).
- i18n registries: `app/javascript/widget/i18n/index.js`, `app/javascript/dashboard/i18n/index.js`, `app/javascript/survey/i18n/index.js`.
- Build tooling: new `vite.lib.config.ts`, `vite.shared.ts`, `vite.sdk.analyze.config.mts`, `vite.widget.analyze.config.mts`; slimmed `vite.config.mts`; `package.json` scripts and devDependency (`rollup-plugin-visualizer`); `lib/tasks/build.rake` precompile hook; removal of `md5` from dependencies.
- SDK runtime: `app/javascript/sdk/DOMHelpers.js`, `cookieHelpers.js`, `IFrameHelper.js`, `sdk.js` → `sdk.css` rename.
- Deploy/serving: `public/packs/js/sdk.js` gains sibling `sdk.js.br` / `sdk.js.gz` assets; web server static-file serving should prefer them when the client advertises support.
