## Why

Upstream Chatwoot v4.14.2 and v4.15.0 shipped a set of dashboard improvements around the global search page, data-dense editing, and message rendering that Konversio (forked at v4.13.0) does not have:

- **Search results page improvements**: paginated "Load more" can skip or duplicate records when new results arrive between page fetches, message search ordering is non-deterministic for ties, search result highlights can break on HTML-like content, and relative timestamps ("2 days ago") give no exact date on hover.
- **Inline images in messages**: on email and website channels, agents cannot paste or insert an image directly into the reply body — images can only go out as attachments. Agents also cannot drag-resize an image inside the editor.
- **Resizable table columns**: Help Center article tables (insertable since v4.13.0) have fixed auto-layout columns; authors cannot drag column borders to size them, and widths are lost on save.
- **Improved message rendering**: messages with a `fallback` attachment type (link-style payloads from channels) render as generic files or not at all, long unbroken content can overflow the bubble grid, and the legacy `Template/*` bubble components are dead code superseded by the consolidated text bubble.

All four items are MIT-licensed upstream changes; the upstream implementation may be referenced and ported verbatim.

## What Changes

- **Search results page** (`app/javascript/dashboard/modules/search/`, `app/services/search_service.rb`):
  - Deduplicate overlapping paginated results by record id in the `conversationSearch` store and track a `hasMore` UI flag per result tab, driven by the raw API page size (15/page).
  - Roll back the page counter when a "Load more" fetch fails so retries re-fetch the same page.
  - Make message search ordering deterministic: `messages.created_at DESC, messages.id DESC` in both the full-text and ILIKE fallback paths of `SearchService`.
  - Include `id` in message search payloads and fall back to the conversation's stored mail subject when the message itself carries none.
  - Render exact localized timestamps on hover over relative dates in result items via a new shared `useExactTimestamp` composable.
  - Restore URL-embedded search filters only after the account (and its feature flags) has loaded; fix the search input lagging one character behind; show voice-call transcripts as message content in results.
- **Inline images in messages** (`WootWriter/Editor.vue`, `@chatwoot/prosemirror-schema` 1.3.10 → 1.4.5):
  - Allow agents to paste a clipboard image (Cmd/Ctrl+Shift+V) or pick an image file directly into the reply body on email and website channels (not private notes); the image is uploaded via the existing account upload endpoint and inserted inline.
  - Replace the legacy preset-size image toolbar with the editor package's drag-resize handle; the chosen width is persisted as a `cw_image_width` query parameter on the image URL.
  - Render `cw_image_width`/`cw_image_height` parameters as inline `<img>` sizing styles in `MessageFormatter`, and add an opt-out `disableImageRendering()` for plain-text contexts.
- **Resizable table columns** (`@chatwoot/prosemirror-schema` 1.4.5, `lib/custom_markdown_renderer.rb`):
  - Enable drag-resizing of article table columns (50px minimum) plus table controls (add/remove rows and columns) in the Help Center article editor.
  - Persist column widths in the article markdown as an internal `<!--cw-colwidths:...-->` comment marker before each resized table; re-apply them when the editor reloads.
  - Strip the marker from all rendered output (`MessageFormatter`) and convert it to a `<colgroup>` + fixed layout when rendering articles for the public portal.
- **Improved message rendering** (`components-next/message/`):
  - Add a `Fallback` bubble that renders `fallback`-type attachments (title + link) instead of dropping them.
  - Prevent bubble overflow from long unbroken content (`min-w-0` on the bubble grid area and base bubble).
  - Remove the dead legacy `bubbles/Template/*` components; template messages render through the standard text bubble.

## Capabilities

### New Capabilities
- `inline-message-images`: Paste, upload, and drag-resize images inline in the reply editor on email and website channels, persisted as sized image URLs in message markdown and rendered with matching sizing in conversation views.
- `resizable-table-columns`: Drag-resizable columns on Help Center article tables, persisted through the markdown round-trip via an internal comment marker, and rendered with fixed column widths on the public portal.

### Modified Capabilities
- `search-results-page`: The existing global search results page gains reliable pagination (dedupe, hasMore, failure rollback), deterministic message ordering, richer message payloads, exact-timestamp tooltips, and safe highlight rendering.
- `message-rendering`: The conversation message list gains a fallback attachment bubble, overflow-safe bubble layout, and removal of dead legacy template bubble components.

## Impact

- `package.json` / `pnpm-lock.yaml`: `@chatwoot/prosemirror-schema` 1.3.10 → 1.4.5 (MIT).
- `app/services/search_service.rb`, `app/presenters/messages/search_data_presenter.rb`, `app/views/api/v1/accounts/search/*.json.jbuilder`.
- `lib/custom_markdown_renderer.rb` (Konversio's Nokogiri-based fork renderer — upstream's node-visitor approach must be adapted, see design).
- `app/javascript/dashboard/store/modules/conversationSearch.js`, `app/javascript/dashboard/modules/search/**`.
- `app/javascript/shared/helpers/MessageFormatter.js`, new `app/javascript/shared/composables/useExactTimestamp.js`.
- `app/javascript/dashboard/components/widgets/WootWriter/Editor.vue`, `FullEditor.vue`.
- `app/javascript/dashboard/components-next/message/` (new `bubbles/Fallback.vue`, `Message.vue`, `bubbles/Base.vue`, `constants.js`).
- English frontend i18n only (`en.json`) for new labels; no database changes.
