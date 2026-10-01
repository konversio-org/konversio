## Why

The Konversio inbox is still on the Chatwoot v4.13.0 conversation experience. Upstream shipped a series of inbox UX improvements across v4.14–v4.18 that agents now consider table stakes: an expanded (full-width) chat list with selectable rows, a reworked bulk-action bar (including bulk label removal), a shared-files attachments panel, quoted email replies, visible/copyable conversation IDs, per-section sidebar sorting, real-time sidebar unread badges backed by a Redis counting service, searchable label assignment in the right-click menu, contact conversation-history navigation, and sortable filtered views. Without these, triage of busy inboxes is slower and sidebar signal (what needs attention, where) is missing.

## What Changes

- **Expanded chat list**: a condensed/expanded layout toggle in the chat list header (persisted via UI settings), with a full-width list using row-style expanded conversation cards on large screens.
- **Bulk actions rework**: split bulk-action bar (agent assignment, team assignment, label assign **and remove**, status/snooze updates with a custom-time modal), select-all, and a guard that skips bulk-resolve for conversations missing required custom attributes.
- **Attachments panel**: a "Shared Files" accordion in the conversation sidebar grouping media and files, with gallery preview (autoplay) and a paginated, eager-loaded attachments endpoint.
- **Quoted email replies**: for email inboxes, an optional per-inbox toggle that appends a quoted copy of the last incoming email (sender, date, sanitized body) to outbound replies, with a preview above the editor.
- **Conversation IDs**: the conversation header shows `#<display id>`; clicking copies it to the clipboard with a confirmation toast.
- **Unread counts and badges**: a Redis-set-backed unread counting service (`Conversations::UnreadCounts::*`), a `GET .../conversations/unread_counts` API, ActionCable push on change, and sidebar unread badges (99+ capped) on inboxes, labels, teams, folders, and the All/Mentions/Participating/Unattended entries. Two feature flags: `conversation_unread_counts` (base) and `unread_count_for_filters` (mentions/participating/unattended/folder counts via snapshot caching). **Final-state note**: the naive per-request filtered counts shipped in upstream v4.15.0 were reverted in v4.15.1 for performance reasons; this change ports only the final snapshot-based implementation present at v4.18.0.
- **Sidebar section sorting**: per-section sort menus (Folders, Teams, Channels, Labels) offering created-at, alphabetical, and unread-count ordering, persisted per user+account in local storage.
- **Context menu label search**: the right-click conversation menu's label submenu gains a fuzzy search box, assigned-labels-first ordering, and an empty state.
- **History navigation + filtered sorting**: older/newer conversation navigation links inside the message thread (backed by a neighbours lookup on the contact conversations endpoint), and a `sort_by` parameter on the conversation filter endpoint applied through `Conversations::SortService`.

## Capabilities

### New Capabilities
- `conversation-unread-counts`: Redis-backed per-inbox/label/team unread counts with realtime push, permission scoping, and feature flags; filtered counts (mentions/participating/unattended/folders) behind a second flag using snapshot caching.
- `sidebar-section-sorting`: Per-section sidebar sort menus with persisted per-user preferences.
- `conversation-history-and-filtered-sort`: Older/newer contact-conversation navigation in the thread, and `sort_by` support on filtered conversation views.
- `conversation-attachments-panel`: Shared Files sidebar panel with media/files grouping and gallery preview.
- `email-quoted-replies`: Optional quoted original email appended to outbound email replies.
- `conversation-context-menu-labels`: Searchable, assigned-first label submenu in the conversation right-click menu.

### Modified Capabilities
- `conversation-list-display`: Expanded/condensed layout toggle, expanded conversation cards, and conversation-ID display/copy in the header.
- `conversation-bulk-actions`: Reworked bulk action bar including bulk label removal and required-attribute-gated bulk resolve.

## Impact

- Backend: new `app/services/conversations/unread_counts/*` services and listener, new `Api::V1::Accounts::Conversations::UnreadCountsController`, `config/features.yml` (two new flags — see design for the bitset constraint), `config/routes.rb`, `app/controllers/api/v1/accounts/contacts/conversations_controller.rb` (neighbours mode), `app/controllers/api/v1/accounts/conversations_controller.rb` (attachments eager-loading, unread-count hooks on `mark_read`/`update_last_seen`), `app/services/conversations/filter_service.rb` (`sort_by` via `Conversations::SortService`), `app/models/conversation.rb` (`sort_on_unread` scope, deletion payload for count maintenance).
- Frontend: chat list components (`ChatList.vue`, new `ConversationList.vue`, `ConversationItem.vue`, `ChatListHeader.vue`), new `components-next/Conversation/ConversationCard/ConversationCardExpanded.vue`, bulk action components (`conversationBulkActions/Bulk{Agent,Label,Team,Update}Actions.vue`), `components-next/SharedAttachments/*` + `SharedFiles.vue`, `ReplyBox.vue` + `helper/quotedEmailHelper.js` + `QuotedEmailPreview.vue`, `ConversationHeader.vue` (ID copy), context menu (`contextMenu/Index.vue`), sidebar (`Sidebar.vue`, `SidebarSortMenu.vue`, `SidebarUnreadBadge.vue`, leaf components), new store modules (`conversationUnreadCounts`, `sidebarSortPreferences`), `useContactConversationNavigation` / `useConversationRoutePath` composables, ActionCable wiring.
- English i18n only (`en.yml` / `en.json`) per project convention.
- All items are upstream MIT code (Chatwoot core tree); verbatim porting is legal — see design.md.
