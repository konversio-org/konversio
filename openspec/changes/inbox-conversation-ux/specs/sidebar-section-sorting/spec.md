## Capability: sidebar-section-sorting

User-controlled ordering of sidebar sections (Folders, Teams, Channels, Labels) via a per-section sort menu (upstream: `helper/sidebarSort.js`, `SidebarSortMenu.vue`, `sidebarSortPreferences` store).

---

## ADDED Requirements

### Requirement: Per-section sort menu

Each of the Folders, Teams, Channels, and Labels sidebar sections SHALL offer a sort menu with six options: newest first, oldest first, name A→Z, name Z→A, most unread first, fewest unread first. The chosen sort MUST apply to that section's entries immediately.

#### Scenario: alphabetical sort

- Given the Labels section contains `urgent`, `billing`, `alpha`
- When the user selects name A→Z
- Then the order is `alpha`, `billing`, `urgent`

#### Scenario: unread-count sort uses sidebar counts

- Given inboxes with unread counts 5, 0, and 12
- When the user selects most unread first for Channels
- Then inboxes order as 12, 5, 0, with alphabetical order breaking ties

#### Scenario: created sort falls back to record ID

- Given entries without a `created_at` value
- When sorted newest first
- Then the record ID is used as the creation proxy

---

### Requirement: Unread sort options gated on unread counts

Unread-count sort options MUST only be offered when unread counts are available for that section: base counts (`conversation_unread_counts`) for Teams/Channels/Labels, and filtered counts (`unread_count_for_filters`) for Folders. A saved unread-count sort MUST degrade to alphabetical (A→Z) when counts become unavailable.

#### Scenario: flag off hides unread options

- Given `conversation_unread_counts` is disabled
- When the user opens the Channels sort menu
- Then only created-at and alphabetical options are shown

#### Scenario: saved unread sort degrades gracefully

- Given the user saved "most unread first" for Channels and the flag is later disabled
- Then Channels render alphabetically A→Z

---

### Requirement: Defaults and persistence

Default sorts SHALL be: Folders newest first; Teams, Channels, and Labels most unread first. Preferences MUST persist per user per account in local storage, and invalid or unknown saved values MUST normalize to the section default.

#### Scenario: defaults on first use

- Given a user who never changed sidebar sorts
- Then Folders are newest first and Teams/Channels/Labels are most unread first

#### Scenario: preference persists per user and account

- Given the user sets Labels to name A→Z on account A
- When the user reloads or switches to another session on account A
- Then Labels are still A→Z
- And account B's preferences are unaffected

#### Scenario: invalid saved value normalizes

- Given local storage contains an unrecognized sort key for Teams
- Then Teams use the section default
