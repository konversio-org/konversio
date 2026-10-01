## Capability: conversation-history-and-filtered-sort

Older/newer navigation through a contact's conversation history inside the message thread, and server-side sorting of filtered conversation views (upstream: `Contacts::ConversationsController#index` neighbours mode, `useContactConversationNavigation.js`, `ContactConversationLink.vue`, `Conversations::SortService` in `FilterService`).

---

## ADDED Requirements

### Requirement: Contact conversation neighbours endpoint

`GET /api/v1/accounts/:account_id/contacts/:contact_id/conversations` SHALL accept an optional `conversation_id` (display ID) parameter. When present, the endpoint MUST return the target conversation plus its immediate older and newer neighbours for that contact, ordered by the `(created_at, id)` tuple, all scoped through conversation permissions. Without the parameter, the endpoint MUST keep its existing behavior (most recent conversations, paginated by 25).

#### Scenario: neighbours returned around the target

- Given a contact with conversations (by creation order) A, B, C, and the user requests `conversation_id` of B
- Then the response payload contains exactly A, B, and C

#### Scenario: boundaries

- Given the same contact and the user requests `conversation_id` of the oldest conversation A
- Then the payload contains only A and B

#### Scenario: permission scoping applies

- Given the requesting agent may not see the inbox of conversation B
- When neighbours are requested for B
- Then the request fails as not found (no cross-inbox leakage)

#### Scenario: default listing unchanged

- Given no `conversation_id` parameter
- Then the endpoint returns the contact's conversations newest-first, limited to 25

---

### Requirement: In-thread history navigation links

When viewing a conversation, the message thread SHALL offer navigation links to the contact's immediate older and newer conversations. Each link MUST show direction (older/newer), the conversation's start date, and a preview of its last message. Navigation MUST preserve the current list context (inbox, label, team, folder, mentions/participating/unattended view) in the target URL. When neighbours cannot be resolved, the links MUST simply not render.

#### Scenario: older link navigates with context

- Given the user opened conversation B from a label-filtered list
- When the user clicks the older-conversation link for A
- Then the app navigates to A within the same label-filtered list context

#### Scenario: newer link suppressed on a live open conversation

- Given conversation B is open and the conversation list is not scoped to this contact
- Then the newer-conversation link is not shown
- (Moving forward is a review action; it must not pull the agent off a live chat.)

#### Scenario: newer link allowed when reviewing resolved or contact-scoped lists

- Given conversation B is resolved, or the list is filtered to this contact
- Then the newer-conversation link to C is shown

#### Scenario: neighbours unavailable

- Given the neighbours request fails or returns nothing
- Then no navigation links render and the thread is unaffected

---

### Requirement: Contact-scoped list suppresses duplicate history panel

When the conversation list is already filtered to a single contact (contact filter applied, condensed layout), the contact panel's "previous conversations" section SHALL be hidden to avoid duplicating the list.

#### Scenario: contact filter active

- Given the list is filtered to contact 42 and conversation of contact 42 is open
- Then the contact panel does not render the previous-conversations section

---

### Requirement: Sorting in filtered views

The conversation filter endpoint SHALL accept a `sort_by` parameter applied through the shared sort service with these keys: `last_activity_at_asc/desc`, `created_at_asc/desc`, `priority_asc/desc`, `waiting_since_asc/desc`, `priority_desc_created_at_asc`, and `unread`. Unknown or missing values MUST fall back to `last_activity_at_desc`. Sorting MUST apply to advanced filters, saved custom views (folders), and contact-filtered views alike, and the active sort MUST be re-sent on pagination and refresh of the filtered list.

#### Scenario: filtered list sorted by created date

- Given a saved folder whose results span multiple days
- When the user requests the folder with `sort_by=created_at_asc`
- Then results are ordered oldest-created first

#### Scenario: invalid sort falls back

- Given `sort_by=bogus`
- When the filter endpoint is called
- Then results use `last_activity_at_desc`

#### Scenario: unread sort

- Given a filtered view with `sort_by=unread`
- Then conversations with unread messages sort first, with last-activity descending breaking ties

#### Scenario: sort preserved across pages

- Given a filtered view sorted by `priority_desc` with multiple pages
- When the user loads the next page
- Then the same `sort_by` is sent and ordering is consistent across pages
