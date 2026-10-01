## Why

Konversio's Help Center lags upstream v4.14.0–v4.18.0 on rich article content. Five concrete gaps:

1. **No AI translation.** Upstream (Enterprise) can translate published articles into a portal's other allowed locales. Konversio articles in multi-locale portals must be translated by hand.
2. **No editor support for URL embeds.** The backend renderer already turns bare YouTube/Loom/Vimeo/etc. links into embedded players on public portal pages, but the article editor shows only the raw link — no live preview, no insert command — so authors cannot see or control what readers get.
3. **Category-blind article creation.** Creating an article from a category view drops it into the first category instead of the one being browsed, and navigates away from the category context.
4. **No analytics integrations.** Portal pages cannot be wired to Google Tag Manager, GA4, Hotjar, Plausible, Amplitude, Microsoft Clarity, or Meta Pixel, so help-center traffic is invisible to standard analytics stacks.
5. **Weak media uploads.** Article image uploads have no progress indication, no retry/cancel, no in-editor previews of pending uploads, no video (MP4) upload path, no image resizing, and nothing stops an author from publishing or navigating away while an upload is still in flight.

## What Changes

- **AI translation (clean-room, EE-origin):** add a bulk "Translate" action on the article list that enqueues per-article Pilot translation jobs into a chosen locale/category; detect existing translations and require explicit overwrite confirmation; create translated articles as drafts linked via `associated_article_id`; implement in the core tree (`Pilot::` namespace, no enterprise overlay).
- **URL embeds (MIT port):** add a "Video" slash-menu command and embed-URL popover to the article editor; render live embed previews in the editor from `config/markdown_embeds.yml`; harden the public renderer (escaped template captures, `hide_source` editor-only embeds, saved embed width via `cw_video_width`).
- **Category-based article creation (MIT port):** add a category-scoped "new article" route that preselects the browsed category and returns to the category context after save.
- **Analytics integrations (MIT port):** store per-portal analytics provider IDs in `portal.config['analytics']` with strict format validation, admin-only writes, and snippet injection into every public portal page; surface the settings in a new Integrations tab of Portal Settings.
- **Media uploads and previews (MIT port):** upload progress cards with retry/cancel/remove, progress/cancellation callbacks through the upload stack, MP4 video upload alongside image upload, image resize handles, and guards that block publish/navigation while uploads are pending.

## Capabilities

### New Capabilities
- `help-center-ai-translation`: Bulk AI translation of Help Center articles into other portal locales via Pilot, with duplicate detection, forced overwrite, and draft creation linked to the source article.
- `help-center-url-embeds`: Insert, preview, and render URL/video embeds in Help Center articles, driven by the shared embed configuration.
- `help-center-category-article-creation`: Create articles pre-assigned to the category the author is browsing, staying in category context.
- `help-center-analytics-integrations`: Per-portal analytics provider configuration (validated, admin-only) injected into public portal pages.
- `help-center-media-uploads`: Robust article media uploads with progress, previews, retry/cancel, video support, image resizing, and pending-upload guards.

### Modified Capabilities
None.

## Impact

- `app/models/portal.rb` (analytics config keys, validation, readers)
- `app/controllers/api/v1/accounts/portals_controller.rb` (admin-only analytics params)
- `app/controllers/api/v1/accounts/articles/bulk_actions_controller.rb` (new; `translate` implemented in core)
- `app/jobs/pilot/articles/translate_job.rb`, `lib/pilot/article_translation_service.rb` (new, clean-room)
- `config/routes.rb` (article bulk actions routes)
- `app/views/layouts/portal.html.erb` + new `app/views/layouts/_portal_analytics*.html.erb` partials
- `app/views/api/v1/accounts/portals/_portal.json.jbuilder` (expose config)
- `lib/konversio_markdown_renderer.rb` / `lib/custom_markdown_renderer.rb`, `config/markdown_embeds.yml` (embed hardening)
- `app/javascript/dashboard/components/widgets/WootWriter/FullEditor.vue`, new `VideoEmbedInput.vue`, new `app/javascript/dashboard/helper/markdownEmbeds.js`
- `@chatwoot/prosemirror-schema` bumped 1.3.10 → 1.4.5 (embed preview, upload, image-resize plugins)
- `app/javascript/dashboard/helper/uploadHelper.js`, `store/modules/helpCenterArticles/actions.js` (progress/abort plumbing)
- `app/javascript/dashboard/routes/dashboard/helpcenter/helpcenter.routes.js` + `PortalsArticlesNewPage.vue` (category-scoped creation)
- New frontend: `BulkTranslateDialog.vue`, `PortalIntegrationsSettings.vue`
- English i18n only (`en.yml`, `en.json`)
- No new database tables; translation linkage reuses `articles.associated_article_id`
