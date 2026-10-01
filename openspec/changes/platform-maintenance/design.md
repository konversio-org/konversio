## Context

Konversio is a hard fork of Chatwoot v4.13.0 with no upstream tracking. Every item in this change corresponds to MIT-licensed upstream work (Chatwoot v4.14.2, v4.16.0, v4.17.0, v4.17.1, v4.18.0), so upstream files and diffs may be referenced directly and verbatim porting is legal. There is no clean-room constraint on this change; nothing here touches the removed `enterprise/` overlay or Pilot.

Current Konversio state vs upstream v4.18.0 (verified against `Gemfile.lock`, `config/initializers/languages.rb`, the i18n index files, and the SDK sources):

- **Rails**: Konversio already upgraded 7.1.5.2 → 7.2.3.1 on its own (`855e076a3`, June 2026), fixed the Rails 7.2 API moves (`2d9a55d35` migration_context-via-pool), added `allow_other_host` to omniauth/devise/slack redirects, and bumped hairtrigger to 1.3.1 (`ea4da5f94`) so `db:schema:dump` works again. Upstream's equivalent landed in v4.17.0 with a slightly different surrounding stack.
- **Puma / OAuth / Vite**: Konversio still runs puma 6.4.3, oauth 1.1.0, oauth-tty 1.0.5, oauth2 2.0.9, vite_rails 3.0.17, vite_ruby 3.8.0. Upstream's v4.14.2+ line ends at puma 7.2.1 (Gemfile pin `~> 7.2, >= 7.2.1`), oauth 1.1.6, oauth-tty 1.0.8, oauth2 2.0.22, vite_rails 3.10.0, vite_ruby 3.10.2. On the JS side Konversio is already *ahead* (vite `^6.3.6`/`^6.4.3`, `@vitejs/plugin-vue` `^6.0.1`) relative to upstream's vite 6.4.2 pin.
- **Locales**: Konversio's `languages.rb`, widget i18n index, dashboard i18n index, and survey i18n index are byte-equivalent to upstream v4.13.0. Estonian and Slovenian translation *files* exist on disk (inherited) but are not registered anywhere. Uzbek does not exist at all. Upstream added Uzbek as a full language (v4.16.0), Slovenian as a full language (v4.17.0), and enabled Estonian in the chat widget (v4.18.0).
- **SDK**: Konversio still uses the v4.13.0-era single `vite.config.mts` with the `BUILD_MODE=library` env-var hack, imports `SDK_CSS` from a synthetic `sdk.js`, and depends on `md5` and `date-fns/addHours` inside the SDK runtime. Upstream v4.17.1 split the SDK into its own Vite config, emitted pre-compressed assets, and removed those dependencies.

## Goals / Non-Goals

**Goals:**

- Verify Konversio's existing Rails 7.2.3.1 migration is complete and correct; reconcile remaining deltas from upstream's upgrade stack deliberately, not by wholesale lockfile replacement.
- Reach version parity with upstream's patched Puma, OAuth-family, and vite_rails/vite_ruby versions without breaking boot, deploy, or the Vite dev workflow documented in `AGENTS.md`.
- Make Uzbek selectable and rendered across backend, dashboard, widget, and survey; make Slovenian selectable and rendered; render Estonian in the chat widget (and dashboard, matching upstream's v4.18.0 registration state).
- Ship the smaller SDK bundle: dedicated build config, single-IIFE output, pre-compressed `.br`/`.gz` artifacts wired into `assets:precompile`, and no `md5`/`date-fns` code in the SDK dependency graph.

**Non-Goals:**

- A fresh Rails 7.2 upgrade — Konversio already did it; this change verifies and reconciles only.
- Adopting upstream's unrelated v4.17.0 Gemfile churn (azure-blob swap, gemoji, firecrawl-sdk, speedshop-cloudwatch, ai-agents/ruby_llm bumps, SafeFetch). Those belong to other parity changes or are out of scope entirely.
- Translating any Konversio-specific or Pilot-specific strings into uz/sl/et. Per repo convention, only `en.yml`/`en.json` are maintained in-repo; the ported upstream locale files cover upstream strings only. Missing keys fall back to English.
- The v4.17.1 "improved widget contact refreshes" behavior change beyond what the hash-algorithm swap strictly requires (see Open Questions).
- JS-side Vite major-version alignment — Konversio is already on Vite 6 ahead of upstream; no downgrade.

## Decisions

### Treat Rails 7.2 as a reconcile/verify task, not an upgrade

Konversio's own migration (PR #54, `855e076a3` + follow-ups) already landed Rails 7.2.3.1, the `alias_attribute`→`alias_method` fix on `User#conversations`, the pool-based `migration_context`, the `allow_other_host` redirect fixes, and the hairtrigger 1.3.1 schema-dump fix. This change adds a verification pass against upstream's v4.17.0 end state and closes only the deltas that matter.

Alternatives considered:
- Re-do the upgrade from upstream's diff. Wasteful and risky: Konversio's tree has diverged (Pilot renames, removed enterprise/), and replaying upstream's migration commits would conflict with work already done.
- Do nothing. The core is on 7.2.3.1, but without a verification pass we cannot claim parity, and upstream's accompanying stack changes (below) would remain unevaluated.

Rationale: the expensive part (framework upgrade + app fixes) is done; what remains is confirmation plus selective adoption of the surrounding dependency stack.

### Selectively adopt upstream's Rails-7.2-adjacent Gemfile changes

Upstream's v4.17.0 stack includes changes worth adopting and changes worth skipping:

- **Adopt: `gem 'rails-i18n', '~> 7.0'`** — provides backend date/time/number formats and pluralization for the locales this change enables (and existing ones). Konversio does not have it.
- **Adopt (evaluate): `devise-secure_password` from the chatwoot git fork → rubygems `2.2.1`** — upstream moved off the same fork Konversio still uses, pinning 2.2.1 because 2.2.3 requires Devise 5. Evaluate during implementation; keep the fork only if 2.2.1 regresses password-policy behavior.
- **Keep Konversio's `gem 'rails', '~> 7.2'`** rather than upstream's exact `'7.2.3.1'` pin — the lockfile already resolves to 7.2.3.1 and the looser pin does not block patch uptake. Revisit if a future 7.2.x breaks us.
- **Skip** azure-blob, gemoji, firecrawl-sdk, speedshop-cloudwatch, and the ai-agents/ruby_llm bumps — unrelated to the assigned changelog items.

### Bump Puma/OAuth/vite_ruby to upstream's patched versions

Match upstream's end state: puma `~> 7.2, >= 7.2.1`, oauth 1.1.6, oauth-tty 1.0.8, oauth2 2.0.22, vite_rails 3.10.0, vite_ruby 3.10.2. The oauth gems are transitive (via omniauth), so they move via targeted `bundle update`, not new Gemfile entries.

Alternatives considered:
- Pin puma to the latest 6.x patch instead of jumping to 7.x. Upstream runs puma 7.2.1 in production with an unchanged `config/puma.rb` (verified: no diff v4.13.0→v4.18.0), so the major-version jump is de-risked; staying on 6.x leaves us diverging from upstream's tested configuration.

Rationale: version parity with upstream's security releases is the cheapest way to close the Dependabot-class alerts the v4.14.2 changelog describes.

### Port upstream locale files verbatim; register what already exists on disk

All locale content is MIT-licensed upstream community translation and is ported verbatim (legal; attribution preserved via git history where practical). Uzbek is a full new language (Rails `config/locales/uz.yml`, dashboard `app/javascript/dashboard/i18n/locale/uz/` ~48 JSON files, widget `uz.json`, survey `uz.json`, `LANGUAGES_CONFIG` entry 42, i18n index registrations). Slovenian files already exist on disk in Konversio — the work is registration: `LANGUAGES_CONFIG` entry 43 plus widget/dashboard/survey i18n index entries. Estonian exists on disk and in `LANGUAGES_CONFIG` (entry 41) — the v4.18.0 work is registering it in the widget i18n index (and the dashboard index, matching upstream's v4.18.0 state).

Alternatives considered:
- Only register languages whose files are 100% key-complete vs `en`. Upstream ships these locales with English fallback for missing keys; gating on completeness would diverge from upstream behavior for no user benefit.
- Skip the survey app (upstream never added Estonian there, even at v4.18.0). We match upstream exactly: survey gets sl + uz, not et.

Rationale: minimal, upstream-matching diff; English fallback makes partial translations safe.

### Split the SDK build into its own Vite config and emit pre-compressed assets

Port upstream's pipeline (MIT, verbatim where it fits): extract shared aliases/vueOptions into `vite.shared.ts`; add `vite.lib.config.ts` building `app/javascript/entrypoints/sdk.js` as a single IIFE (`inlineDynamicImports: true`) to `public/packs/js/sdk.js`, with a plugin emitting `sdk.js.br` (brotli, max quality) and `sdk.js.gz`; add `build:sdk` and `analyze:bundle:{sdk,widget}` scripts with `rollup-plugin-visualizer`; hook `build:sdk` into `assets:precompile` via `lib/tasks/build.rake`; delete the `BUILD_MODE=library` branch from `vite.config.mts`.

Alternatives considered:
- Keep the `BUILD_MODE=library` env toggle. It works but keeps one config serving two masters, cannot emit per-build compressed artifacts cleanly, and diverges from upstream's now-tested structure for no gain.
- Serve compression via the reverse proxy only. Pre-compressed static assets are free at runtime and upstream emits them; Konversio is self-hosted with varied proxies, so emitting the files (and documenting that the static file server should prefer them) is the portable choice.

Rationale: matches upstream's proven structure, shrinks transfer size via pre-compression, and simplifies the main config.

### Slim the SDK runtime: FNV-1a instead of md5, Date math instead of date-fns, `?inline` CSS

Port upstream's SDK runtime changes: rename `app/javascript/sdk/sdk.js` → `sdk.css` and import it as `import SDK_CSS from './sdk.css?inline'` in `DOMHelpers.js`; replace the `md5` package with an in-file FNV-1a 128-bit hash (BigInt) in `cookieHelpers.js`; replace `date-fns/addHours` with `new Date(Date.now() + 60 * 60 * 1000)` in `IFrameHelper.js`; remove `md5` from `package.json`.

Alternatives considered:
- Keep md5 (small, already worked). The point of the upstream change is exactly this: every byte in the SDK ships to every visitor of every customer's site; md5 + its dependency chain is dead weight once a ~30-line BigInt hash suffices.
- Keep the md5 hash *values* for cookie-compatibility by reimplementing md5 inline. Rejected: the hash only feeds change-detection on the `cw_user_*` cookie; a one-time algorithm change causes a single benign contact refresh per returning visitor, which upstream accepted.

Rationale: the SDK is Konversio's most widely distributed artifact; dependency removal is the durable size win.

## Risks / Trade-offs

- **Puma 6 → 7 major jump** -> Upstream runs 7.2.1 with an unchanged `config/puma.rb`; still, smoke-test boot, the healthcheck endpoint, and WebSocket (ActionCable) behavior in container mode before merging.
- **Hash-algorithm change invalidates existing `cw_user_*` cookies** -> Accept a one-time extra contact refresh per returning widget visitor; call this out in the changelog.
- **FNV-1a uses BigInt** -> The SDK's browser matrix must support BigInt (all evergreen browsers do); confirm the build target doesn't transpile it away or break on the oldest supported browser.
- **Partial translations** -> uz/sl/et files cover upstream strings only; Konversio/Pilot-specific strings render in English. Accepted per repo i18n convention.
- **`vite.config.mts` vs upstream's `.ts`** -> Konversio renamed the config to `.mts`; keep the `.mts` extension and adapt upstream's `.ts` additions accordingly (naming-only difference).

## Migration Plan

1. Land dependency bumps and locale changes first — both are additive/low-risk and independently revertible via `git revert` + `bundle install`.
2. Land the SDK build-pipeline split and runtime slimming together; rollback is reverting the build files and restoring `md5`/`date-fns` imports — no data or schema changes involved at any step.
3. No database migrations, no production data fixes.

## Open Questions

- Upstream bundled a `getUserString` data-shape change (additional contact-information attributes in the user hash input, serialized as JSON) into the same SDK area as the md5→FNV-1a swap, under the separate v4.17.1 changelog line "improved widget contact refreshes". needs investigation: whether that attribute expansion is required for the hash swap to behave correctly, or belongs to a separate parity change; this spec scopes only the dependency-removal part.
- Upstream added `rails-i18n` alongside the Rails 7.2 upgrade; needs investigation: confirm rails-i18n 7.0.x ships uz/sl/et pluralization and date formats (it is expected to, but verify at bundle time).
