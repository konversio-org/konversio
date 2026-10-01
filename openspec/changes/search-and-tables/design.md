## Context

Konversio forked Chatwoot at v4.13.0. The global search results page (`app/javascript/dashboard/modules/search/`, tabs All/Contacts/Conversations/Messages/Articles, advanced filters behind the `ADVANCED_SEARCH` feature flag) already exists at the fork base, as do Help Center article tables (insertable via the slash menu) and image height-resizing in the message signature editor. Upstream v4.14.2 and v4.15.0 then landed four related improvement sets that this change ports to reach parity with v4.18.0:

- Search page reliability/polish (pagination dedupe + `hasMore`, deterministic ordering, payload and highlight fixes, exact-timestamp tooltips).
- Inline images in the reply editor for email and website channels.
- Resizable article table columns with width persistence.
- Message rendering fixes (fallback attachment bubble, overflow fixes, dead code removal).

**License axis: MIT for everything in this change.** Upstream Chatwoot CE and the `@chatwoot/prosemirror-schema` npm package are MIT-licensed, so referencing upstream files and porting code verbatim is legal. Upstream references below name real upstream paths at tag v4.18.0.

One structural divergence matters: Konversio rewrote `lib/custom_markdown_renderer.rb` as a Nokogiri HTML post-processor (`process_article_html`), while upstream v4.18.0 uses CommonMarker node visitors (`table(node)`, `html(node)`). The column-width rendering port must be adapted to Konversio's renderer shape rather than copied line-for-line.

## Goals / Non-Goals

**Goals:**

- Reach feature parity with upstream v4.15.0-era search page behavior: no skipped or duplicated pages, deterministic ordering, safe highlights, exact timestamps on hover.
- Allow inline image paste/upload/drag-resize in the reply editor on email and website channels, persisted in message markdown and rendered consistently in dashboard and widget.
- Allow drag-resizing of article table columns in the Help Center editor, with widths surviving save/reload and rendering fixed-width on the public portal.
- Render `fallback` attachments with a dedicated bubble; fix bubble overflow; delete dead legacy template bubble code.
- Port from upstream where the trees align (MIT); adapt only where Konversio diverged.

**Non-Goals:**

- Reworking the search page layout, adding new tabs, or changing the `ADVANCED_SEARCH` flag's scope.
- ElasticSearch-backed search behavior changes (ordering fix applies to both pg full-text and ILIKE fallback paths only).
- WhatsApp referral/Flow-response bubbles, voice-call bubbles, and Pilot generation details that also touched `components-next/message/` upstream — owned by `whatsapp-platform`, `voice-calling`, and the `pilot-*` changes respectively.
- Video embeds (`cw_video_width`) in the editor and portal renderer — owned by `help-center-rich-content`.
- The staged-edits article diff panel (`ArticleDiffPanel.vue`, upstream v4.16) — owned by `help-center-revamp`; this change only notes where column widths must be honored if that panel exists.
- Upstream's `MarkdownRendererUrlSanitizer` and other v4.18.0 rendering-security hardening — owned by `channel-and-security-hardening`.
- Any database migration: no schema changes are required.

## Decisions

### Port search pagination fixes from upstream verbatim

Port the `conversationSearch` store changes from upstream v4.18.0: `PER_PAGE = 15`, `appendUniqueRecords` id-based dedupe on all four record lists, `hasMore` UI flags set from the raw response page size, and boolean success returns from each search action; plus the `SearchView.vue` changes: `showLoadMore` reads `hasMore`, `loadMore` rolls back the page counter on failure, and URL filter restore waits for `currentAccount.id`.

Alternatives considered:
- Server-driven `has_more` pagination metadata in every search response. More robust but changes four API contracts and diverges from upstream for no user-visible gain.
- Keep concat-without-dedupe and only fix ordering. Ordering alone does not prevent duplicates when records are inserted between page fetches.

Rationale: the upstream fix is small, self-contained, and already accounts for the failure-rollback edge case; verbatim port minimizes regression risk.

### Make message search ordering deterministic in SearchService

Port the upstream one-liner in `app/services/search_service.rb`: order by `messages.created_at DESC, messages.id DESC` in both the full-text (`to_tsquery`) and ILIKE fallback paths, so ties never shuffle between pages.

Rationale: non-deterministic tie ordering is the root cause of records appearing twice or vanishing across pages; the id tiebreaker fixes it at the database with zero application complexity.

### Bump `@chatwoot/prosemirror-schema` to 1.4.5 instead of vendoring

The inline-image and table-column features live mostly in the upstream npm package (MIT): `imageResizeView` (corner drag handle committing a pixel width attr), `imagePastePlugin`, `insertImageFiles`/`findNodeToInsertImage`, upload state/overlay plugins, `isolateImages`, `columnResizing({ cellMinWidth: 50 })` + `tableControlsPlugin`, and the article markdown serializer/parser that round-trips the `<!--cw-colwidths:...-->` marker. Konversio consumes this package from npm today (1.3.10); bump to 1.4.5.

Alternatives considered:
- Vendor/fork the package into the repo. Upstream develops it out-of-tree already; vendoring creates a permanent maintenance fork for zero licensing need (MIT) and no functional divergence today.
- Reimplement the node views and plugins in `app/javascript`. Hundreds of lines of editor internals duplicated for no benefit.

Rationale: the package is MIT and already a dependency; the bump is the upstream-intended integration path.

### Gate inline image paste to email and website channels only

Match upstream: `allowsInlineImagePaste` is true only when the reply is not a private note and the effective channel is email or website. Paste uses Cmd/Ctrl+Shift+V with `navigator.clipboard.read()` (the native paste event does not carry image bytes for this gesture); the image is uploaded through the existing `POST /api/v1/accounts/:accountId/upload` endpoint (4 MB limit) and inserted as an image node via `findNodeToInsertImage`. The same insertion path backs the toolbar/menu image picker.

Alternatives considered:
- Enable on all channels. API channels (WhatsApp, etc.) cannot deliver inline body images — they would silently degrade to broken markdown for contacts.
- Attach images as regular attachments instead. That is the status quo and exactly what the feature replaces.

Rationale: upstream's gate reflects which channels can actually deliver inline images (HTML email, web widget markdown rendering).

### Persist image width and table column widths in the markdown itself

Match upstream's persistence format: image sizing rides on the image URL as `cw_image_width=<N>px` (width takes precedence; legacy `cw_image_height` still honored), and table column widths are serialized as a `<!--cw-colwidths:w1,w2,...-->` comment (0 = unset) immediately before each resized table. `MessageFormatter` strips the marker from every rendered/plain-text output and translates the image params into inline `style` attributes.

Alternatives considered:
- Store widths in a separate document metadata column. Requires schema changes, new API surface, and diverges from upstream article compatibility.
- Render the marker as harmless visible text. Unacceptable: it leaks into search snippets and the widget.

Rationale: self-describing markdown keeps the round-trip editor↔storage↔portal lossless with zero schema change, and the strip rule guarantees the internal marker never surfaces.

### Adapt portal column-width rendering to Konversio's Nokogiri renderer

Upstream v4.18.0 intercepts the marker in `CustomMarkdownRenderer#html` and injects a `<colgroup>` + fixed-layout wrapper in `#table`. Konversio's fork renderer instead post-processes `Nokogiri::HTML.fragment(html)` in `process_article_html`. Port the *behavior*, not the shape: while walking the fragment, read `cw-colwidths` comment nodes preceding each table, inject a `<colgroup>` (unset widths default to the 50px editor minimum), apply `table-layout: fixed`, and size the existing `.tableWrapper` to the summed width (capped at `max-width: 100%`).

Alternatives considered:
- Revert Konversio's renderer to upstream's node-visitor version to make the port verbatim. The fork's rewrite is deliberate (embed/superscript handling); reverting risks regressions outside this change's scope.
- Leave portal tables auto-layout. Authors' sizing intent would silently vanish for readers.

Rationale: behavior-parity with upstream while respecting the fork's renderer architecture.

### Add a shared `useExactTimestamp` composable for result item tooltips

Port upstream's `app/javascript/shared/composables/useExactTimestamp.js` verbatim: locale-cached `Intl.DateTimeFormat` with medium date/short time and forced Gregorian calendar, optional timezone suffix, empty string for missing timestamps; use it for hover tooltips on the relative dates in search result items (contacts, conversations, messages, articles).

Rationale: shared composable (not search-local) because relative-time tooltips are a recurring need; caching matters because it runs in the render path.

### Add a Fallback bubble and drop dead Template bubbles

Port upstream's `components-next/message/bubbles/Fallback.vue` (renders `fallback`-type single attachments as title + external link, with formatted content above when present) and route `ATTACHMENT_TYPES.FALLBACK` to it in `Message.vue`; add `NON_FILE_TYPES` to `constants.js`; apply `min-w-0` to the bubble grid area and base bubble; delete `bubbles/Template/*` and their stories (template messages fall through to the standard text bubble, as upstream does).

Alternatives considered:
- Keep the Template bubble files. They are unreferenced after the consolidation upstream; keeping them is dead code and future drift.
- Render fallback attachments as generic file bubbles. Loses the title/link semantics channels rely on.

## Risks / Trade-offs

- **Package bump surface area** — `@chatwoot/prosemirror-schema` 1.3.10 → 1.4.5 also changes editor behaviors beyond this change (upload overlays, isolate-images normalization). Mitigate by smoke-testing all editor surfaces (reply box, private notes, message signature, article editor) after the bump.
- **Marker format coupling** — `cw-colwidths` and `cw_image_width` are parsed in three places (editor package, `MessageFormatter`, portal renderer). They are upstream's canonical formats; do not rename them, and keep the MessageFormatter strip regex tolerant of blockquote prefixes as upstream does.
- **Clipboard API availability** — `navigator.clipboard.read()` requires secure context and permission; the upstream pattern fails silently and leaves normal text paste untouched, which the port must preserve.
- **XSS surface in search highlights** — port the upstream ordering exactly: markdown → plain text → HTML-escape → inject only the highlight `<span>` → render via `v-dompurify-html`. Do not reintroduce `highlightContent` on unescaped content.

## Migration Plan

1. Bump `@chatwoot/prosemirror-schema` to 1.4.5 and port the frontend editor/formatter/search/message changes in one deploy; all are additive or behavior-correcting, no data migration.
2. Port the backend search ordering/payload changes and the portal renderer change in the same deploy — the marker only appears in articles after editors start saving resized tables, so renderer support should land no later than the editor bump.
3. Rollback: revert the package bump and ports; existing articles containing markers render as before (marker stripped from output), and messages with sized images fall back to unsized rendering.

## Open Questions

- If `help-center-revamp` lands the staged-edits diff panel (`ArticleDiffPanel.vue`) first, it must re-apply `cw-colwidths` in its markdown preview as upstream does; coordinate ordering between the two changes.
- needs investigation: whether Konversio's Pilot document views (the fork's counterpart of upstream's captain `DocumentDetails.vue`) should adopt `MessageFormatter#disableImageRendering()` immediately or when the Pilot document-detail UI lands; the method itself ships with this change.
