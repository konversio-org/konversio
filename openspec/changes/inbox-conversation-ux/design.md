## Context

Konversio forked Chatwoot at v4.13.0. Upstream delivered the inbox UX items covered here across v4.14.0, v4.14.1, v4.15.0/4.15.1, v4.16.2, and v4.18.0. Because Konversio has no upstream tracking, each item is a deliberate port from the upstream tag diff `v4.13.0..v4.18.0`.

**License axis: MIT for every item in this change.** All referenced code lives in the upstream core tree (`app/`, `app/javascript/`, `config/`, `db/`), not in `enterprise/`. Chatwoot's core is MIT, so verbatim porting is legal and preferred where the code applies unchanged. Where upstream code references things Konversio removed or renamed (Captain → `Pilot::`, Chatwoot branding, `enterprise/` hooks), the port adapts naming rather than forking behavior.

One upstream complication matters for the port: upstream's `feature_flags` bitset column is full (63/63 slots), so upstream *repurposed* two deprecated flags — `channel_twitter` became `conversation_unread_counts` (migration `20260508000000_repurpose_channel_twitter_flag_for_conversation_unread_counts.rb`) and `quoted_email_reply` became `unread_count_for_filters` (migration `20260629000000_repurpose_quoted_email_reply_flag_for_unread_count_for_filters.rb`). Konversio inherits the same v4.13.0 bitset layout, so the same repurposing is the lowest-risk path.

## Goals / Non-Goals

**Goals:**

- Port the final v4.18.0 state of each assigned changelog item; skip superseded intermediate implementations (notably the reverted v4.15.0 naive filtered unread counts).
- Keep all behavior in the core tree; no `enterprise/` paths, no Captain references.
- Preserve Konversio renames: `Pilot::` where upstream says Captain; Konversio product naming in user-facing copy; branded-instance copy via `replaceInstallationName` where applicable.
- Feature-flag the unread count systems (default off) so self-hosters opt in deliberately.

**Non-Goals:**

- Voice/call features that share the same upstream files (e.g. `ConversationCallButton`, voice-call rows in expanded cards) — covered by a separate parity change.
- Companies, contact filters (`contact_id` filter key), and other v4.14+ inbox-adjacent items assigned to other change documents.
- Backfilling or migrating historical data; the unread count store is rebuilt on demand from the database.
- Porting upstream's `spec/enterprise` unread-count variants.

## Decisions

### Port upstream implementation directly (MIT), adapting renames

Upstream references per item:

- Expanded chat list: `ChatList.vue` refactor extracting `ConversationList.vue`, `ConversationCardExpanded.vue` (new, `components-next/Conversation/ConversationCard/`), layout toggle in `ChatListHeader.vue` keyed off `conversation_display_type` UI setting, `isOnExpandedLayout` in `composables/useUISettings.js`.
- Bulk actions: `composables/chatlist/useBulkActions.js`, `conversationBulkActions/{Index,BulkAgentActions,BulkLabelActions,BulkTeamActions,BulkUpdateActions}.vue`. Bulk label **removal** is frontend-only: the v4.13.0 backend `bulk_actions_controller.rb` already permits `labels: [add: [], remove: []]`.
- Attachments: `routes/dashboard/conversation/SharedFiles.vue`, `components-next/SharedAttachments/{Media,Files}.vue`, `GalleryView.vue` autoplay, eager-loading in `conversations_controller#attachments`.
- Quoted replies: `helper/quotedEmailHelper.js`, `QuotedEmailPreview.vue`, ReplyBox integration, per-inbox UI-settings flag.
- Conversation IDs: `ConversationHeader.vue` `#<id>` button + `copyTextToClipboard`.
- Unread counts: `app/services/conversations/unread_counts/*`, `unread_counts_controller.rb`, `store/modules/conversationUnreadCounts.js`, `SidebarUnreadBadge.vue`, ActionCable event `conversation.unread_count_changed` (`lib/events/types.rb`).
- Sidebar sorting: `helper/sidebarSort.js`, `SidebarSortMenu.vue`, `store/modules/sidebarSortPreferences.js`.
- Context-menu label search: `contextMenu/Index.vue` using `@chatwoot/pico-search`.
- History + sorting: `Contacts::ConversationsController#index` neighbours mode, `useContactConversationNavigation.js`, `ContactConversationLink.vue`, `Conversations::SortService.apply` in `FilterService`.

Alternatives considered:
- Reimplementing from scratch: pointless cost for MIT code that already matches our architecture.
- Cherry-picking per-release states: the v4.15.0 filtered counts were reverted for performance in v4.15.1; porting intermediate states would import a known regression.

Rationale: the fork base is v4.13.0 and the upstream diff applies to the same file layout; direct porting minimizes divergence and review surface.

### Unread counts: Redis set-membership store, not SQL COUNTs

The base counter (`UnreadCounts::Counter`) reads Redis sets keyed by account/inbox(/label/team)(/assignee), built lazily by `UnreadCounts::Builder` from open conversations with incoming messages newer than `agent_last_seen_at`, maintained incrementally by `UnreadCounts::Refresher` on message/status/assignee/team/label events via `UnreadCounts::Listener`, and pushed to clients with a `conversation.unread_count_changed` broadcast (scoped to the account and the conversation's inbox members). Sets TTL at 25h, readiness flags at 24h; builds are lock-guarded (`Redis::LockManager`) with a bounded wait.

Alternatives considered:
- SQL `COUNT` per request (upstream v4.15.0's first attempt for filtered counts): reverted upstream for performance on large accounts; do not port.
- Postgres-only materialized counts: adds write amplification on every message; Redis sets are O(1) membership and naturally expire.

Rationale: this is the final upstream design and is proven against the performance complaint that killed the naive version.

### Filtered unread counts behind a separate flag with snapshot caching

Mentions/participating/unattended counts and per-folder counts ship only under `unread_count_for_filters`, computed by `UnreadCounts::FilteredCounter` with version-stamped snapshots (fresh 5 min, stale-servable up to 1h), at most 3 inline filter builds per request, and version-bump invalidation (`FilteredCountInvalidator`) on conversation changes, mentions, and custom-filter/attribute-definition edits.

Alternatives considered:
- Dropping filtered counts entirely (v4.15.1's revert state): loses assigned scope — the changelog item says "unread counts … and filter support," and the final state includes them.
- Merging both flags into one: upstream deliberately separated them so instances can adopt base counts without the heavier filtered path.

### Sidebar sorting is client-side and local-storage persisted

Per-section sort (Folders/Teams/Channels/Labels; created_at asc/desc, alphabetical asc/desc, unread-count asc/desc) is computed in the frontend from already-fetched lists plus unread counts, persisted in localStorage scoped by `userId:accountId`. Unread-count options are hidden when the corresponding unread-count flag is off; saved unread-count sorts degrade to alphabetical.

Alternatives considered:
- Persisting via the UI settings API: upstream chose local storage; following them avoids a server migration and matches per-device preference semantics.

### History navigation uses a neighbours query, not a full history list

`GET /api/v1/accounts/:account_id/contacts/:contact_id/conversations?conversation_id=<display_id>` returns only the target conversation plus its immediate older/newer neighbours (tuple comparison on `(created_at, id)`), permission-filtered. The newer link is suppressed for open conversations unless the list is already contact-scoped, so agents don't "walk away" from a live chat accidentally.

Alternatives considered:
- Loading the full contact history client-side and computing neighbours: wasteful for contacts with long histories; upstream's scoped query is bounded.

### Naming and branding adaptations for the port

- Any upstream UI copy containing "Chatwoot" is replaced with Konversio-appropriate copy, using `replaceInstallationName` where the string should adapt to branded installs.
- The localStorage key `chatwoot_sidebar_sort_preferences` is renamed (e.g. `konversio_sidebar_sort_preferences`); no migration needed since the store is cosmetic.
- `window.chatwootConfig` references port as-is if Konversio keeps that global, otherwise to the Konversio equivalent — needs investigation during implementation (check what the fork renamed the global to).

## Risks / Trade-offs

- **Redis dependency grows**: the unread count store assumes Redis (Alfred) is always available; the API degrades by rebuilding on demand, and the frontend ignores fetch failures so the sidebar renders badgeless rather than erroring.
- **Feature-flag repurposing**: reusing `channel_twitter`/`quoted_email_reply` slots requires upstream's cleanup migrations (disable on accounts that had the old flag, scrub `ACCOUNT_LEVEL_FEATURE_DEFAULTS`) — port both migrations verbatim.
- **Stale filtered counts**: snapshots can serve up to ~1h stale under invalidation lag; acceptable for badges, documented in the spec.
- **File-level collisions with other parity changes**: `ReplyBox.vue`, `ConversationHeader.vue`, `Sidebar.vue`, and `ConversationCard.vue` are touched by multiple v4.14–4.18 changes; implementation order should land this change's hunks per-file rather than per-feature to avoid rebase churn.

## Migration Plan

1. Add the two repurposed feature flags via the upstream cleanup migrations (both flags end default-off).
2. Port backend unread-count services, controller, routes, listener registration.
3. Port frontend store modules, sidebar badges/sort menus, chat list/bulk actions/context menu/quoted reply/attachments/header changes.
4. Enable `conversation_unread_counts` per account via super admin when ready; `unread_count_for_filters` only after base counts are stable.
5. Rollback: disable flags; unread UI hides (frontend clears state when the flag is off). All other items are additive UI and can be reverted by revert-commit.

## Open Questions

- Does Konversio keep `window.chatwootConfig.hostURL` (used when ctrl/cmd-clicking a conversation card to open in a new tab)? — needs investigation in the fork's frontend boot code.
- Upstream's unread-count services assume `assignee_agent_bot_id` semantics; Konversio v4.13.0 base matches, but the polymorphic `ai_assignee` rename in upstream v4.18.0 touches the same models — confirm the port lands on Konversio's `assignee_agent_bot_id` (not `ai_assignee`) to avoid dragging in the unrelated assignee refactor.
