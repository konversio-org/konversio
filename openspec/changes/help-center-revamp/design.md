## Context

Konversio forked Chatwoot at v4.13.0. Upstream then shipped a large Help Center revamp across v4.14.0–v4.16.0. This change adopts that revamp. All items in this change are **MIT-licensed upstream work in the core tree** — direct porting, including verbatim file ports, is legal and preferred where the upstream implementation is clean. Reference points (upstream tag `v4.18.0` in `/tmp/chatwoot-upstream`):

- `app/models/portal.rb`, `app/models/concerns/portal_config_schema.rb`, `app/models/article.rb`
- `app/controllers/api/v1/accounts/{portals,articles,categories}_controller.rb`, `app/controllers/api/v1/accounts/articles/bulk_actions_controller.rb`
- `app/controllers/public/api/v1/portals*` (incl. new `search_controller.rb`), `app/controllers/concerns/portal_home_data.rb`
- `app/views/public/api/v1/portals/**` (incl. `*.html+documentation.erb` variants and `documentation_layout/` partials), `app/views/layouts/portal.html*.erb`
- `app/javascript/dashboard/components-next/HelpCenter/**`, `app/javascript/dashboard/helper/portalHelper.js`, `articleDiffHelper.js`
- `db/migrate/20260610000000_add_icon_color_to_categories.rb`, `db/migrate/20260623000000_add_draft_columns_to_articles.rb`

Konversio adaptations while porting:

- **No enterprise overlay.** Upstream's `prepend_mod_with(...)` calls and `Enterprise*` hooks are dropped; code lands directly in the core files.
- **Bulk article translation is upstream-Enterprise (Captain).** Core upstream ships `Articles::BulkActionsController#translate` as `head :not_implemented`, with the real implementation in `enterprise/app/controllers/enterprise/api/v1/accounts/articles/bulk_actions_controller.rb` calling Captain. Konversio has no enterprise tree; the `translate` action is **out of scope** for this change. A Pilot-based bulk translation can be proposed separately.
- Upstream reuses `components-next/captain/assistant/BulkSelectBar.vue` for the article bulk bar; Konversio's equivalent shared component is `components-next/bulk-action/BulkSelectBar.vue` — use that.
- Upstream uses `components-next/emoji-icon-picker/`; verify whether it exists in Konversio and port it if missing.
- The upstream revamp also added portal analytics integrations (`config.analytics`) in v4.17.0 — that is **not** part of this change's scope and is intentionally excluded (separate parity item). `PortalConfigSchema` upstream includes the analytics key because the v4.18.0 snapshot is post-v4.17; our port may omit analytics or leave it as a reserved-but-rejected key.

## Goals / Non-Goals

**Goals:**

- Port the v4.14.0–v4.16.0 help center feature set listed in the proposal into Konversio's core tree, MIT-clean.
- Keep public portal URLs stable: existing `/hc/:slug/:locale/...` links keep working; portals without a configured layout render exactly as before (`classic`).
- Preserve data integrity: reorder rebalancing fixes position collisions in place; staged drafts never leak to the public site; config merges never drop keys written by a concurrent save.
- Spec and implement against Konversio naming (`Pilot::` where AI is touched — none here) and core-tree-only paths.

**Non-Goals:**

- Bulk AI translation of articles (upstream Enterprise/Captain feature).
- Portal analytics/tracking snippets (`config.analytics`, v4.17.0 upstream item).
- Help Center AI article generation during onboarding (upstream Enterprise/Captain).
- Renaming or restructuring the existing `classic` layout markup beyond what the new variants require.
- Non-English frontend i18n.

## Decisions

### Store new portal configuration in `config` jsonb with a JSON-schema-validated concern

Adopt upstream's `PortalConfigSchema` concern: `locale_translations` and `popular_content` get strict per-key schemas; `layout` is an enum of `classic|documentation`; `social_profiles` is an open object. `Portal#normalize_config` merges incoming config onto the persisted config (instead of replacing it) and the update action takes a row lock (`@portal.lock!`) so concurrent saves don't clobber each other's keys.

Alternatives considered:
- New columns per setting. Layout/branding/popular content are sparse, per-portal, and evolve fast; columns would mean a migration per addition.
- Replace-merge of config (v4.13.0 behavior). Upstream hit real key-loss bugs from concurrent saves; the merge-plus-lock fix is part of what we port.

Rationale: matches upstream exactly, keeps the change reviewable against the upstream diff, and fixes a real data-loss race.

### Implement layouts as Rails view variants (`+documentation`, `+plain`)

The public portal controllers set `request.variant` from `portal.layout` (`Public::Api::V1::Portals::BaseController#set_portal_layout` / `set_view_variant`), and templates/partials exist per variant (`show.html+documentation.erb`, `documentation_layout/_sidebar.html.erb`, etc.). Unknown/blank layout values fall back to `classic`.

Alternatives considered:
- A separate Vue SPA for the documentation layout. Upstream already has a server-rendered portal; a second SPA would double maintenance.
- Layout as a CSS-only theme. The documentation layout has different structure (sidebar navigation, table of contents, different hero) — CSS alone can't express it.

Rationale: view variants are the upstream-proven mechanism and keep one request pipeline.

### Public search is a server-rendered page, not a JSON autocomplete

New `Public::Api::V1::Portals::SearchController#index` at `/hc/:slug/:locale/search` renders paginated (10/page) results using the existing `Article.search` pg_search scope, restricted to published articles in the requested locale. To keep `/hc/:slug/:locale/search` and `/hc/:slug/articles/:article_slug` from colliding, `Article::RESERVED_SLUGS = %w[search articles categories]` are excluded in validation.

Alternatives considered:
- JSON API + client-side rendering. The portal is server-rendered; a JSON endpoint would need a JS results page and hurts SEO/no-JS visitors.
- Reusing the widget search suggestions endpoint. That returns a small suggestion list, not a full results page.

Rationale: consistent with the portal's server-rendered architecture; the reserved-slug guard is a small upstream-proven addition.

### Stage published-article edits in `draft_title`/`draft_content` columns

Autosaves on a **published** article write `draft_title`/`draft_content` only, via `update_columns` after explicit validation, so the public record and its `updated_at` (used by sitemaps/feeds) are untouched. On non-published articles, edits save directly to `title`/`content`, and any leftover staged draft is promoted into the save and cleared so a later publish can't resurrect stale content. Publishing a staged article promotes the draft (`title: draft_title`, `content: draft_content`, null drafts) in one update; discarding nulls the drafts. The UI shows an "unpublished changes" state, a pending-changes popover on status changes, and a diff panel comparing draft vs live (title word-by-word, body block-by-block, with a CommonMark render-equality check so whitespace-only edits don't count).

Alternatives considered:
- Version history table. Heavier; upstream chose two nullable columns, which covers the single-draft workflow.
- Autosave directly to live columns behind a "preview". That is the pre-revamp behavior and is exactly the problem (live articles mutate while editing).

Rationale: two columns + frontend diff is the upstream design, small to port, and solves the stated problem.

### Bulk actions run synchronously in a dedicated controller, not the conversation `BulkActionsJob`

`Api::V1::Accounts::Articles::BulkActionsController` (nested under portals) exposes `POST translate` (→ 501), `PATCH update_status`, `PATCH update_category`, `DELETE delete_articles`, each validating inputs and wrapping updates in a transaction. Conversation bulk actions go through `BulkActionsJob`, but articles are fewer and the operations are trivial — upstream deliberately kept them synchronous.

Alternatives considered:
- Extend `BulkActionsJob` with an Article model type. Adds job plumbing, progress tracking, and permission-filter coupling for operations that complete in one transaction.
- Reuse single-article update endpoints in a client loop. Loses atomicity and validation of the target category/status.

Rationale: matches upstream; synchronous transactions are correct at help-center scale.

### Reorder rebalances positions and returns the final map

`Article.update_positions` applies the client's `positions_hash`, then re-spaces every touched category to 10-step positions (stable sort by current position, moved articles last, then id) and returns `{ article_id => position }` so the client can sync without a refetch. The endpoint renders the map as JSON instead of a bare `head :ok`.

Alternatives considered:
- Fractional positions. Harder to keep consistent across paginated lists.
- Client refetch after every reorder. Upstream explicitly avoids refetch on same-page reorders; returning final positions is what enables that.

Rationale: position collisions were a live bug; rebalancing in one transaction is the upstream fix.

### Popular content and branding are per-locale config, curated by admins

`popular_content[locale]` holds ordered `category_ids` (max 3 surfaced) and `article_ids` (max 6); `locale_translations[locale]` holds `name`, `page_title`, `header_text` overrides with fallback to the default-locale override, then the base column (`Portal#localized_value`). The portal home data (`PortalHomeData#load_home_data`) uses curated picks when present and falls back to position-ordered categories / most-viewed articles. The locale page gets "customize content" and "select popular content" dialogs.

Alternatives considered:
- Fully automatic popularity (views only). Views-based "featured" stays the fallback; admins want editorial control per locale.
- One global curation list. Locales differ in content; per-locale keys are the upstream model.

Rationale: mirrors upstream exactly; fallback behavior means existing portals are unchanged until curated.

### Category icons add `icon_color` alongside the existing `icon` string

The category form gains an emoji/icon picker with a color swatch; `icon` stores the emoji or icon name, `icon_color` the color (blank for emoji). Icons surface in the admin article category selector and on public category blocks.

Rationale: smallest schema change (one nullable column), matches upstream.

## Risks / Trade-offs

- **Big-bang port** -> This change bundles five releases of upstream work. Mitigate by landing backend-first per capability (each section of tasks.md is independently shippable) and reviewing against the upstream diff.
- **`update_columns` skips callbacks for staged autosaves** -> Deliberate: it preserves `updated_at`. The controller validates before writing, so column-limit overflows can't persist.
- **Reserved slugs** -> Articles already named `search`/`articles`/`categories` would fail validation on next edit. Upstream accepted this; our spec requires the same and notes it in Impact.
- **Config merge semantics** -> Deep-merge of `locale_translations`/`popular_content` means a client cannot delete a locale key by omission; needs investigation: exact deletion semantics upstream (whether dialogs send explicit empty values to clear keys).
- **View-variant templates** -> The documentation layout markup is large; port it verbatim from upstream `app/views/public/api/v1/portals/**` and `app/views/layouts/portal.html+documentation.erb` rather than re-deriving it.

## Migration Plan

1. Migrations first: `icon_color` on categories, `draft_title`/`draft_content` on articles. Both nullable, additive, instant.
2. Backend: `PortalConfigSchema`, portal model/controller changes, bulk actions controller, article staging + reorder, public search controller + routes. All additive; existing portals default to `layout = classic`.
3. Frontend admin: settings tabs, locale dialogs, bulk bar, editor staging/diff UI, category icon picker.
4. Public: documentation layout variants, search page, social footer, localized branding.
5. Rollback: revert deploy; new columns and config keys are additive and ignored by the old code (old code validates `config` keys against `CONFIG_JSON_KEYS` — a rollback would reject saves of portals that have the new keys; mitigate by keeping `CONFIG_JSON_KEYS` superset-compatible or accepting config-only no-op on rollback).

## Open Questions

- Bulk article translation: fold a Pilot-based implementation into this change later, or a separate OpenSpec change? (Recommended: separate.)
- Does the upstream locale dialog clear a locale's overrides by sending empty strings, or by key omission with special handling? Confirm against `LocaleContentDialog.vue` during implementation.
- `components-next/emoji-icon-picker/` presence in Konversio must be verified; if absent it is ported from upstream as part of the category-icons capability.
