## Context

Konversio's Help Center sits at upstream v4.13.0 plus fork-specific changes. The public article renderer was already rewritten once (Nokogiri-based `CustomMarkdownRenderer`, invoked via `KonversioMarkdownRenderer#render_article` from `app/controllers/public/api/v1/portals/articles_controller.rb`) and already converts isolated bare links into embeds using `config/markdown_embeds.yml`. The article editor (`FullEditor.vue`, ProseMirror via `@chatwoot/prosemirror-schema` 1.3.10) has no embed preview, no video insert command, and a fire-and-forget image upload with no progress or abort support.

Upstream delivered the assigned items across three releases:

- **v4.14.0** — AI article translation (**Enterprise-only**: `enterprise/app/controllers/enterprise/api/v1/accounts/articles/bulk_actions_controller.rb`, `enterprise/app/jobs/captain/articles/translate_job.rb`, `enterprise/app/services/captain/llm/article_translation_service.rb`); category-based article creation (core/MIT); URL embed groundwork (core/MIT).
- **v4.17.0** — Help Center analytics integrations + live-chat widget relocation into a new Integrations settings tab (core/MIT: `Portal::ANALYTICS_CONFIG_FORMATS`, `app/views/layouts/_portal_analytics.html.erb`, `PortalIntegrationsSettings.vue`); editor video embeds (core/MIT).
- **v4.18.0** — Help Center media upload UX: progress cards, retry/cancel, MP4 upload, image resize, pending-upload publish/navigation guards (core/MIT).

## License split

- **AI translation is EE-origin → clean-room, requirements-level.** Upstream files were read for understanding only. The spec expresses behavior (endpoint contract, duplicate handling, job semantics, LLM preservation rules) in original wording. Implementation lands in the **core tree** under the `Pilot::` namespace (`app/jobs/pilot/articles/translate_job.rb`, `lib/pilot/article_translation_service.rb`), gated by the existing `pilot_tasks` feature flag. The bulk-translate dialog (`BulkTranslateDialog.vue`) and the core controller shell live in upstream's MIT core tree and may be ported directly.
- **Everything else is MIT** (upstream core tree). Verbatim porting is legal; tasks reference upstream files and may copy them with adaptation to Konversio's renamed renderer and branding (`replaceInstallationName` where upstream copy says "Chatwoot").

## Goals / Non-Goals

**Goals:**

- Bulk-translate articles to another allowed portal locale, creating linked drafts, with overwrite protection.
- Editor insert command + live preview for all configured embed types; public rendering hardened (escaped captures, embed width, editor-only embeds).
- Create articles in the category being browsed; return to category context.
- Per-portal analytics provider IDs, validated and admin-only, injected on every public portal page.
- Upload progress/retry/cancel, MP4 video upload, image resizing, pending-upload guards on publish and navigation.

**Non-Goals:**

- Staged edits for published articles (draft_title/draft_content), article diff panel, article reordering, admin search — covered by other parity changes.
- Non-translation bulk actions (status/category/delete) — same.
- New portal layouts (documentation layout), social profiles, popular content, per-locale branding — v4.14.1/v4.15 items owned elsewhere.
- Translating categories, portal settings copy, or anything other than article title/content.
- Translating on demand for a single article from the editor (bulk list action only, matching upstream scope).

## Decisions

### Implement translation in the core controller, not an overlay (clean-room)

Add `POST /api/v1/accounts/:account_id/portals/:portal_id/articles/bulk_actions/translate` handled directly in the core `Api::V1::Accounts::Articles::BulkActionsController` (upstream ships a core shell whose `translate` returns `501` and an EE module that prepends the real behavior). Konversio has no `enterprise/` tree, so the behavior goes straight into the core controller, enqueueing `Pilot::Articles::TranslateJob` per article.

Alternatives considered:
- Recreate upstream's prepend-module structure in `app/` — pointless indirection now that there is no OSS/EE split.
- Single synchronous translation request — rejected: translating N articles × 2 LLM calls each cannot fit a request cycle; async per-article jobs also isolate failures.

Rationale: matches Konversio's "edit core files freely" rule and keeps retry/failure granularity per article.

### Translation job semantics (clean-room)

Per article: resolve the root article (`Article.find_root_article_id`), translate title then content through a `Pilot::Llm`-style task service (`lib/pilot/article_translation_service.rb` extending `Pilot::BaseTaskService`, using `Llm::Config.model_for(:default)`), then update the existing same-locale translation of that root or create a **draft** article in the target locale/category authored by the requesting user, linked via `associated_article_id`.

The LLM instructions are specified as requirements, not ported text: translate only visible text; preserve all markdown structure, HTML tags/attributes, URLs, image references, iframes, embeds, code blocks, and whitespace exactly; return only the translation. (Upstream prompt wording was NOT copied; see clean-room rule.)

Alternatives considered:
- Translate description too — upstream deliberately reuses the source description untranslated; we keep parity (needs investigation: confirm this is desired product behavior for Konversio).
- HTML-aware post-processing to guarantee tag preservation — rejected for v1; requirement-level prompt rules plus human review of drafts suffice.

### Duplicate detection before enqueueing

Before enqueueing, find target-locale articles already linked to any selected root. If any exist and the request did not set `force`, respond `409 Conflict` with the conflicting article ids/titles so the UI can show an overwrite-confirmation state; with `force`, proceed and the job updates in place.

Alternatives considered:
- Silently overwrite — destroys existing reviewed translations without consent.
- Skip duplicates silently — leaves authors thinking everything was translated.

### Editor embeds driven by the shared YAML config (MIT port)

Port upstream `app/javascript/dashboard/helper/markdownEmbeds.js`: import `config/markdown_embeds.yml`, exclude non-previewable embeds (GitHub gist, which relies on `document.write`), and feed `{regex, template, hideSource}` entries to `embedPreviewPlugin` from `@chatwoot/prosemirror-schema` 1.4.5. A "Video" slash-menu command opens `VideoEmbedInput.vue` (ported), which accepts either a supported embed URL (inserted as a bare linked paragraph, matching what the public renderer recognizes) or an uploaded MP4.

Alternatives considered:
- Duplicate embed regexes in JS constants — rejected; the YAML is already the single source of truth for the backend renderer.
- Custom ProseMirror embed node — rejected; upstream's "bare link + preview overlay" keeps markdown serialization unchanged.

### Renderer hardening on Konversio's existing renderer (MIT port)

Konversio's Nokogiri-based renderer already does embed replacement; port upstream v4.18's behavioral fixes onto it: HTML-escape captured values before template substitution (current Konversio code injects them raw — an XSS vector on crafted URLs), honor `hide_source` (editor-only embeds such as MP4), apply saved embed width from the `cw_video_width` link query param as a wrapping container, and apply the `[^&/?]+` capture fixes to `config/markdown_embeds.yml`.

needs investigation: Konversio's `config/markdown_embeds.yml` lacks the `mp4` key that upstream already had at v4.13.0 — confirm whether the fork removed it deliberately before re-adding it for MP4 embeds.

Alternatives considered:
- Adopt upstream's rewritten `CommonMarker::HtmlRenderer` subclass wholesale — rejected for this change; Konversio's renderer diverged intentionally and the behavioral fixes are portable onto it.

### Analytics config in `portal.config['analytics']`, admin-only (MIT port)

Port `Portal::ANALYTICS_CONFIG_FORMATS` (per-provider id format allowlist: GTM, GA4, Hotjar, Plausible, Amplitude, Clarity, Meta Pixel), validate in the model, permit the `analytics` config key only for administrators in `PortalsController`, expose `config.analytics` in `_portal.json.jbuilder`, and render `app/views/layouts/_portal_analytics.html.erb` (+ noscript variant) from the portal layout on every public page. Port `PortalIntegrationsSettings.vue` as a new Integrations tab; the existing live-chat-widget selector moves there from base settings.

Rationale for admin-only: these values inject third-party scripts into every public page; format validation additionally guarantees values are safe to interpolate (no quotes/brackets).

Alternatives considered:
- A separate `portal_integrations` table — rejected; config blob with strict validation is upstream's proven shape and avoids a migration.
- Allowing knowledge-base editors (non-admins) to set analytics — rejected; script injection is an account-security surface.

needs investigation: whether public portal pages are served with a Content-Security-Policy that would need `script-src`/`frame-src` additions for analytics and embed domains.

### Category-scoped article creation route (MIT port)

Add route `portals_categories_articles_new` (`:portalSlug/:locale/categories/:categorySlug/articles/new`) in `helpcenter.routes.js`; `PortalsArticlesNewPage.vue` resolves the category from `categorySlug`, preselects it, and after create redirects to the category-scoped edit route; "back" returns to the category article list. Fallback when no slug matches: first category (current behavior).

### Editor upload pipeline with progress and abort (MIT port)

Thread `onProgress` and `AbortSignal` through `uploadHelper.js` (`uploadFile`, `uploadExternalImage`) and `helpCenterArticles` store actions into the prosemirror-schema 1.4.5 upload plugins (`insertImageFiles`, `insertFileUploads`, `fileUploadPlugin`, `setUploadLabels`). Gate file types in one place (`bucketFor`): images ≤ 4 MB, `video/mp4` ≤ account `maximumFileUploadSize`; block new uploads while a create dispatch is in flight (`uploadsBlockedMessage`); expose `hasPendingUploads()` (active uploads or error cards) and use it to gate publish and route-leave with an alert.

Rationale: the package already ships the upload-card UI; porting beats building a parallel implementation.

## Risks / Trade-offs

- **prosemirror-schema 1.3.10 → 1.4.5** — major editor surface bump; needs investigation: confirm 1.4.5 is the minimum version exporting `embedPreviewPlugin`, `fileUploadPlugin`, `insertImageFiles`, `insertFileUploads`, `hasActiveUploads`, `setUploadLabels`, `imageResizeView`, `trailingParagraphPlugin`, and that intermediate releases don't force unrelated schema changes. Verify against upstream v4.18.0's lockfile.
- **LLM translation fidelity** — translations land as drafts precisely so humans review; still, markdown/media preservation must be spec-tested with fixtures (article with table + image + embed + code block).
- **Analytics script injection** — mitigated by strict id formats + admin-only writes; CSP question flagged above.
- **Scope overlap** — `ArticleEditor.vue`/`ArticleEditorHeader.vue` upstream diffs mix this change's upload guards with the staged-edits change; port only the upload-related parts here and let the staged-edits change own the draft machinery.

## Migration Plan

1. Backend-only first: routes + bulk translate controller + Pilot job/service behind `pilot_tasks`; portal analytics config + partials (inert until configured); renderer hardening (behavior-preserving for existing content).
2. Frontend: editor upgrade + embed/upload UX; Integrations settings tab; category creation route; bulk translate dialog.
3. Rollback: feature-flag off translation; remove Integrations tab and partial renders (config keys harmlessly remain); revert editor to 1.3.10 — articles with embeds degrade to plain links, which the public renderer still upgrades to embeds for readers.

## Open Questions

- Should translation also cover the article description, or keep parity with upstream (source description reused untranslated)?
- Does Konversio want the `mp4` embed key restored in `config/markdown_embeds.yml` (see needs-investigation above)?
- Confirm public portal CSP requirements for analytics/embed third-party domains.
