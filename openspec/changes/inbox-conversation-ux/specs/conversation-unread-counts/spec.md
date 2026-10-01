## Capability: conversation-unread-counts

Real-time unread conversation counts for the dashboard sidebar, backed by a Redis set-membership store (upstream: `app/services/conversations/unread_counts/*`, `unread_counts_controller.rb`, store module `conversationUnreadCounts`, `SidebarUnreadBadge.vue`).

This is the FINAL upstream state: the naive per-request filtered counts shipped in upstream v4.15.0 and reverted in v4.15.1 are NOT part of this spec; filtered counts exist only via the snapshot-cached implementation behind `unread_count_for_filters`.

---

## ADDED Requirements

### Requirement: Unread definition

A conversation SHALL count as unread for the sidebar when it is open AND has at least one incoming message created after the conversation's `agent_last_seen_at` (or `agent_last_seen_at` is null). Resolved, pending, and snoozed conversations MUST NOT contribute.

#### Scenario: new incoming message makes a conversation unread

- Given an open conversation whose `agent_last_seen_at` is in the past
- When a new incoming message arrives
- Then the conversation counts as unread

#### Scenario: reading clears unread

- Given an unread conversation
- When the agent's `agent_last_seen_at` advances past the newest incoming message
- Then the conversation no longer counts as unread

#### Scenario: non-open statuses excluded

- Given a resolved conversation receives a new incoming message without reopening
- Then it does not contribute to unread counts

---

### Requirement: Unread counts API

`GET /api/v1/accounts/:account_id/conversations/unread_counts` SHALL return `{ payload: { all_count, inboxes, labels, teams } }` where `inboxes`/`labels`/`teams` map IDs to positive counts and `all_count` is the total. When `unread_count_for_filters` is also enabled, the payload MUST additionally include `mentions_count`, `participating_count`, `unattended_count`, and a `folders` map. The endpoint MUST return 403 when `conversation_unread_counts` is disabled.

#### Scenario: flag disabled

- Given the account does not have `conversation_unread_counts` enabled
- When the endpoint is called
- Then the response is 403 with a feature-not-enabled error

#### Scenario: base counts shape

- Given the flag is enabled and inboxes 3 and 7 have 2 and 5 unread conversations
- Then the payload is `{ all_count: 7, inboxes: { "3": 2, "7": 5 }, labels: {...}, teams: {...} }`
- And IDs with zero unread are omitted from the maps

#### Scenario: label counts cover sidebar labels only

- Given labels `vip` (show on sidebar) and `internal` (not shown on sidebar)
- Then only `vip` appears in the labels map

---

### Requirement: Permission-scoped counts

Counts MUST reflect what the requesting user may see: administrators count all inboxes and teams; agents count only their member inboxes and teams. For custom-role agents the counts MUST follow conversation permissions: `conversation_manage` → all visible conversations; `conversation_unassigned_manage` → unassigned plus assigned-to-me; `conversation_participating_manage` → only assigned-to-me; no conversation permission → all-zero counts.

#### Scenario: agent sees own inboxes only

- Given an agent is a member of inbox 3 but not inbox 7
- Then the counts include inbox 3 and exclude inbox 7

#### Scenario: unassigned-and-mine custom role

- Given a custom-role agent with `conversation_unassigned_manage`
- Then counts include unassigned conversations and conversations assigned to that agent, but not conversations assigned to others

#### Scenario: no conversation permission

- Given a custom-role agent with no conversation permissions
- Then the payload contains zero counts

---

### Requirement: Redis set store with lazy build and incremental refresh

Counts SHALL be served from Redis sets keyed by account, inbox, label, team, and assignee, built on demand from the database in batches (with a distributed build lock and bounded wait), and refreshed incrementally on incoming message creation, conversation status change, assignee change, team change, label change, and conversation deletion. Readiness flags MUST expire (24h) and membership sets MUST expire (25h) so the store self-heals by rebuilding.

#### Scenario: cold cache builds on demand

- Given no unread-count sets exist for the account
- When the unread counts endpoint is called
- Then the store is built from open unread conversations and counts are returned

#### Scenario: assignment move updates counts

- Given conversation 10 is unread, in inbox 3, assigned to agent A
- When it is reassigned to agent B
- Then assignment-scoped counts move from A's keys to B's keys without a full rebuild

#### Scenario: deletion removes memberships

- Given unread conversation 10 is deleted
- Then it is removed from all sets and a count-changed broadcast is emitted using the deletion payload

---

### Requirement: Realtime push

When any conversation's unread membership changes, the system SHALL dispatch a `conversation.unread_count_changed` event broadcast to the account and the conversation's inbox members. The dashboard MUST refetch counts (debounced) on this event and on local conversation mutations, and MUST NOT error when the fetch fails.

#### Scenario: badge updates without reload

- Given the sidebar shows inbox 3 with badge 2
- When a new incoming message arrives in an unread conversation in inbox 3
- Then the badge updates to 3 without a page reload

#### Scenario: fetch failure keeps sidebar usable

- Given the unread counts request fails
- Then the sidebar renders without badges and no error is surfaced to the user

---

### Requirement: Filtered counts via snapshot caching

When `unread_count_for_filters` is enabled, mentions, participating, and unattended counts and per-folder (conversation custom view) counts SHALL be computed from version-stamped Redis snapshots: fresh for 5 minutes, servable stale for up to 1 hour while a refresh is claimed, with at most 3 inline folder-count builds per request. Snapshots MUST be invalidated by version bumps when conversations change, when the user's mention/participation visibility changes, and when conversation custom filters or conversation custom attribute definitions are created, updated, or destroyed.

#### Scenario: folder count served from snapshot

- Given a folder snapshot was built 2 minutes ago
- When the endpoint is called
- Then the folder count is served from the snapshot without querying the database

#### Scenario: custom filter edit invalidates its count

- Given a folder snapshot exists for custom filter 9
- When filter 9's query is changed
- Then the next request rebuilds filter 9's count

#### Scenario: invalid filter count is dropped

- Given a custom filter whose query no longer validates
- When its count is rebuilt
- Then the stored count is deleted and the folder is omitted from the payload

---

### Requirement: Sidebar unread badges

Sidebar entries for inboxes (channels), sidebar labels, teams, folders, and the All/Mentions/Participating/Unattended conversation entries SHALL display an unread badge showing the count, capped at `99+`. Badges MUST be hidden when the count is zero or the governing flag is disabled, and MUST appear in both expanded and collapsed sidebar presentations.

#### Scenario: badge rendering

- Given inbox 3 has 120 unread conversations
- Then its sidebar badge shows `99+`

#### Scenario: zero count hides badge

- Given inbox 3 has no unread conversations
- Then no badge is rendered for inbox 3

#### Scenario: flag disabled clears state

- Given the account's `conversation_unread_counts` flag is turned off
- Then the dashboard clears stored counts and renders no badges
