## Tasks

### Backend

1. - [ ] **Rails 7.2 verification** — confirm `Gemfile.lock` resolves rails/actionpack/activerecord/railties to 7.2.3.1, `db/schema.rb` carries the `[7.2]` version stamp with hairtrigger triggers intact, and `gem 'rails', '~> 7.2'` stays in place; boot the app in host and container mode and run the full `bundle exec rspec` suite to confirm the existing migration (`855e076a3`, `2d9a55d35`, `ea4da5f94`, allow_other_host fixes) is complete.
2. - [x] **rails-i18n** — add `gem 'rails-i18n', '~> 7.0'` to the Gemfile (matching upstream v4.18.0); verify it loads and provides date/pluralization data for `uz`, `sl`, `et` (`rails runner 'puts I18n.t("date.formats", locale: :uz).inspect'` etc.).
3. - [x] **devise-secure_password evaluation** — compare Konversio's current git-fork source (`github: 'chatwoot/devise-secure_password', branch: 'chatwoot'`) against upstream's rubygems pin `2.2.1`; switch to the pinned gem if behavior is equivalent, otherwise record why the fork stays.
4. - [x] **Puma bump** — set `gem 'puma', '~> 7.2', '>= 7.2.1'` in the Gemfile, `bundle update puma`, confirm `config/puma.rb` needs no changes (upstream's is byte-identical v4.13.0→v4.18.0), and smoke-test boot, the Sidekiq healthcheck path, and ActionCable in container mode.
5. - [x] **OAuth family bump** — `bundle update oauth oauth-tty oauth2` to reach oauth 1.1.6, oauth-tty 1.0.8, oauth2 2.0.22 (transitive via omniauth gems; no new Gemfile entries); run the Google/Facebook/Instagram omniauth callback specs and verify `allow_other_host` redirect behavior still passes.
6. - [x] **vite_rails/vite_ruby bump** — `bundle update vite_rails vite_ruby` to vite_rails 3.10.0 / vite_ruby 3.10.2; verify `bin/vite dev` HMR still works in host mode and `assets:precompile` succeeds in container mode.
7. - [x] **Uzbek Rails locale** — port upstream `config/locales/uz.yml` verbatim (MIT) into `config/locales/uz.yml`.
8. - [x] **LANGUAGES_CONFIG** — add `42 => { name: 'Oʻzbekcha (uz)', iso_639_3_code: 'uzb', iso_639_1_code: 'uz', enabled: true }` and `43 => { name: 'slovenščina (sl)', iso_639_3_code: 'slv', iso_639_1_code: 'sl', enabled: true }` to `config/initializers/languages.rb`; confirm `Rails.configuration.i18n.available_locales` and the `Account.locale` enum pick up both, and that existing enum indexes are unchanged.
9. - [x] **SDK precompile hook** — port upstream `lib/tasks/build.rake`: a `before_assets_precompile` task running `pnpm run build:sdk`, enhanced onto `assets:precompile`, so `public/packs/js/sdk.js{,.br,.gz}` ship with every deploy.

### Frontend

10. - [x] **Uzbek locale files** — port upstream verbatim (MIT): `app/javascript/dashboard/i18n/locale/uz/` (full directory, ~48 JSON files), `app/javascript/widget/i18n/locale/uz.json`, `app/javascript/survey/i18n/locale/uz.json`.
11. - [x] **Widget i18n registry** — in `app/javascript/widget/i18n/index.js`, import and register `et`, `sl`, and `uz` (files for et/sl already exist on disk, unregistered).
12. - [x] **Dashboard i18n registry** — in `app/javascript/dashboard/i18n/index.js`, import and register `et`, `sl`, and `uz` (et/sl locale directories already exist on disk, unregistered).
13. - [x] **Survey i18n registry** — in `app/javascript/survey/i18n/index.js`, import and register `sl` and `uz` only; do NOT add `et` (upstream has no Estonian survey locale at v4.18.0).
14. - [x] **Shared Vite config extraction** — create `vite.shared.ts` exporting `aliases` and `vueOptions` (port from upstream); slim `vite.config.mts` (keep the `.mts` extension) to import from it and delete the entire `BUILD_MODE=library` branch and its library-mode rollup options.
15. - [x] **SDK build config** — port upstream `vite.lib.config.ts`: lib-mode IIFE build of `app/javascript/entrypoints/sdk.js` with `inlineDynamicImports: true`, output `public/packs/js/sdk.js`, and the `compress-sdk` plugin emitting max-quality brotli (`sdk.js.br`) and gzip (`sdk.js.gz`) assets via `node:zlib`.
16. - [x] **Bundle analysis configs** — port upstream `vite.sdk.analyze.config.mts` and `vite.widget.analyze.config.mts`; add `rollup-plugin-visualizer` 7.0.1 as a devDependency and the `build:sdk`, `analyze:bundle:sdk`, `analyze:bundle:widget` scripts to `package.json`.
17. - [x] **SDK CSS inline** — rename `app/javascript/sdk/sdk.js` to `app/javascript/sdk/sdk.css` and change `app/javascript/sdk/DOMHelpers.js` to `import SDK_CSS from './sdk.css?inline'`.
18. - [x] **SDK hash swap** — in `app/javascript/sdk/cookieHelpers.js`, remove the `md5` import and implement upstream's FNV-1a 128-bit BigInt hash (`fnv1a128`) for `computeHashForUserData`; remove `"md5"` from `package.json` dependencies.
19. - [x] **SDK date-fns removal** — in `app/javascript/sdk/IFrameHelper.js`, replace `addHours(new Date(), 1)` with `new Date(Date.now() + 60 * 60 * 1000)` and drop the `date-fns/addHours` import from the SDK graph.
20. - [x] **Vite JS version check** — confirm the lockfile resolves `vite` to ≥ 6.4.2 (Konversio's `^6.3.6`/`^6.4.3` ranges already exceed upstream's 6.4.2 pin; keep `@vitejs/plugin-vue` `^6.0.1`, do not downgrade to upstream's `^5.2.4`).

### Validation

21. - [ ] **Backend suite** — `bundle exec rspec` green on the full suite; `bundle exec rubocop` clean on touched files.
22. - [x] **Frontend suite** — `pnpm test` and `pnpm eslint` green; add/extend a spec asserting `getUserCookieName`/`computeHashForUserData` behavior if the existing `app/javascript/sdk` specs cover cookie helpers (match existing spec patterns, no new scaffolding).
23. - [ ] **SDK build verification** — `pnpm run build:sdk` produces `public/packs/js/sdk.js` plus `.br`/`.gz` siblings; record the bundle-size delta vs the previous `BUILD_MODE=library` build in the PR description; load the widget from the built SDK in a local page and complete a conversation round-trip.
24. - [ ] **Locale smoke tests** — set an account locale to `uz`, `sl`, `et` and verify: dashboard renders the ported translations (with English fallback for Konversio/Pilot-specific strings), the chat widget renders widget translations for all three, the survey renders for `sl`/`uz`, and backend mailer/error strings resolve via `config/locales/uz.yml`.
25. - [ ] **Boot/deploy smoke** — full container-mode boot (`docker compose up -d`) with puma 7.2.x: app serves, Sidekiq processes a job, ActionCable streams, and `assets:precompile` in a clean checkout runs `build:sdk` automatically.
26. - [x] **needs investigation: widget contact refresh scope** — determine whether upstream's `getUserString` contact-information attribute expansion (bundled upstream with the hash swap, changelogged separately as "improved widget contact refreshes") must ride along; if yes, spec it in a follow-up change rather than expanding this one silently.

## Dependencies / Order

- Task 1 gates everything (it confirms the Rails baseline the rest builds on). Tasks 2–6 are independent of each other and of the frontend track.
- Tasks 7–8 (backend locales) and 10–13 (frontend locales) are independent per file but must all land before task 24; task 8 must land before account-locale selection works end to end.
- Task 14 → 15 → 16 are sequential (shared extraction, then lib config, then analyze configs/scripts). Tasks 17–19 are independent of 14–16 but must land before task 23. Task 9 depends on 15 (needs `build:sdk`).
- Task 20 is a lockfile inspection; run it alongside 14–16.
- Tasks 21–25 validate the whole chain; 26 may conclude after merge without blocking it.
