## Why

Konversio's Help Center is still the v4.13.0 implementation. Upstream shipped a multi-release Help Center revamp between v4.14.0 and v4.16.0 that we want to adopt: a documentation-style portal layout with a layout switcher (v4.14.1, refined in v4.15.0), server-rendered public search and per-locale portal branding (v4.14.2), per-locale settings and category icons (v4.15.0), article bulk actions (v4.14.0, plus bulk category changes in v4.14.1), and staged edits for published articles, admin-side article search, drag-to-reorder with position rebalancing, and per-locale popular content (v4.16.0).

Today, editors cannot revise a live article without the changes going public immediately, cannot reorder articles reliably (position collisions), cannot find articles by text in the admin UI, and portal owners cannot brand or curate the portal per locale. Visitors get a single fixed layout and no search results page.

## What Changes

- **Portal configuration model** (`app/models/portal.rb`): accept and validate new `config` keys — `layout`, `social_profiles`, `locale_translations`, `popular_content` — via a new `PortalConfigSchema` concern with JSON-schema validation; add `Portal#layout`, `#localized_value`, `#popular_category_ids`, `#popular_article_ids`, `#social_profiles`; merge incoming config onto persisted config under a row lock so concurrent saves don't drop keys.
- **Documentation layout** for public portals: `classic` (current) and `documentation` view variants for portal home, category, article, and search pages, selected per portal; unknown layouts fall back to `classic`.
- **Public help center search**: new server-rendered search results page at `GET /hc/:slug/:locale/search` backed by the existing pg_search scope, paginated; reserved article slugs (`search`, `articles`, `categories`) to avoid route collisions.
- **Per-locale portal branding**: per-locale overrides of portal `name`, `page_title`, and `header_text` stored in `config.locale_translations`, resolved with fallback to the default-locale override and then the base column; locale page gets "customize content" and "select popular content" dialogs.
- **Popular content by locale**: per-locale curated category (max 3) and article (max 6) picks for the portal home page, with fallbacks to position-ordered categories and most-viewed articles.
- **Category icons**: new `icon_color` column on `categories`; emoji/icon picker in the category form; icons rendered in the admin article category selector and on public portal pages.
- **Article bulk actions**: new `Api::V1::Accounts::Articles::BulkActionsController` with `update_status`, `update_category`, `delete_articles` (transactional, validated), plus selection UI and bulk action bar on the articles list page. The upstream `translate` action is Enterprise-only (Captain); core returns `501` — out of scope here (a Pilot-based follow-up can fill it).
- **Staged edits for published articles**: new `draft_title` / `draft_content` columns on `articles`; autosaves on a published article write the draft columns without touching the live record or bumping `updated_at`; editors see an "unpublished changes" state with a diff panel and can publish (promote draft) or discard it; stale drafts are promoted-and-cleared when an article leaves the published status.
- **Admin article search**: search input on the articles list page wired to the existing `query` index param, with abortable (debounced) requests and URL `?search=` sync.
- **Article reordering**: drag-to-reorder uses the shared `DraggableReorderList`; the `reorder` endpoint returns rebalanced positions (`Article.update_positions` now re-spaces affected categories to 10-step positions and returns the final hash).
- **Article editor improvements**: resizable table columns persisted via a `<!--cw-colwidths:...-->` marker rendered to sized tables by `CustomMarkdownRenderer`; image width serialization; video embed node in the editor schema; toolbar options unavailable inside table cells are disabled.

## Capabilities

### New Capabilities
- `portal-layout-and-branding`: Per-portal documentation layout with layout switcher, per-locale branding overrides (name, page title, header text), social profile links, and per-locale popular content curation.
- `help-center-public-search`: Server-rendered public search results page per portal locale, with reserved slugs protecting search routes.
- `article-bulk-actions`: Bulk status change, category reassignment, and deletion for help center articles from the admin UI.
- `staged-article-edits`: Draft title/content staging on published articles so edits don't go live until explicitly published, with diff preview and discard.
- `category-icons`: Emoji or icon plus color for help center categories, shown in admin pickers and on public portals.
- `article-editor`: Editor improvements for help center articles — resizable table columns, sized images, video embeds, and table-context toolbar constraints.

### Modified Capabilities
- None.

## Impact

- `articles` table: new `draft_title`, `draft_content` columns (migration).
- `categories` table: new `icon_color` column (migration).
- `portals.config` jsonb: new validated keys (`layout`, `social_profiles`, `locale_translations`, `popular_content`); update path gains a row lock.
- New files: `app/models/concerns/portal_config_schema.rb`, `app/controllers/api/v1/accounts/articles/bulk_actions_controller.rb`, `app/controllers/concerns/portal_home_data.rb`, `app/controllers/public/api/v1/portals/search_controller.rb`, documentation-layout view variants and partials under `app/views/public/api/v1/portals/` and `app/views/layouts/`, plus locale/popular-content dialogs, bulk action bar wiring, diff panel, and pending-changes popover in `app/javascript/dashboard/components-next/HelpCenter/`.
- Modified: `app/models/portal.rb`, `app/models/article.rb`, `app/controllers/api/v1/accounts/{articles,portals,categories}_controller.rb`, public portal controllers, `lib/custom_markdown_renderer.rb`, help center dashboard pages (`PortalsArticlesEditPage.vue`, `ArticlesPage.vue`, `ArticleList.vue`, `CategoryForm.vue`, `PortalSettings*.vue`), `app/javascript/dashboard/helper/portalHelper.js`, new `app/javascript/dashboard/helper/articleDiffHelper.js`, `config/routes.rb`, `config/markdown_embeds.yml`.
- Public routes: new `GET /hc/:slug/:locale/search`, named route helpers for portal pages; article slugs `search`, `articles`, `categories` become reserved (existing articles with those slugs keep working via the database but can no longer be renamed to a reserved slug).
- English frontend i18n only for new labels and copy (`en.json`); other locales are community-maintained.
