## Capability: conversation-list-display

Conversation list layout modes (condensed/expanded) and conversation ID visibility in the header.

---

## ADDED Requirements

### Requirement: Expanded chat list layout

The conversation list SHALL support two layout modes — condensed (default, fixed-width list beside the message pane) and expanded (full-width list) — selectable from a layout toggle in the chat list header. The selection MUST be persisted per user via the UI settings key `conversation_display_type`.

#### Scenario: toggle switches layout and persists

- Given a user is on the conversation list in condensed layout
- When the user activates the layout toggle in the chat list header
- Then the list switches to expanded layout
- And the preference is saved to UI settings and restored on the next session

#### Scenario: expanded layout uses expanded conversation cards on large screens

- Given expanded layout is active and the viewport is at least the large-screen breakpoint
- Then each conversation row renders as an expanded card showing selection checkbox, contact avatar and name, message preview, inbox name (when not in an inbox view), labels, assignee, priority, SLA state, and timestamp

#### Scenario: expanded cards fall back to condensed on small screens

- Given expanded layout is active and the viewport is below the large-screen breakpoint
- Then conversation rows render as condensed cards

#### Scenario: message pane hidden when nothing selected in expanded layout

- Given expanded layout is active and no conversation is selected
- Then the message pane is not shown; the list occupies the full content width

---

### Requirement: Conversation ID display and copy in header

The conversation header SHALL display the conversation's display ID as `#<id>`; clicking it MUST copy the ID to the clipboard and show a success confirmation.

#### Scenario: ID is visible in the header

- Given a conversation with display ID 1234 is open
- Then the header shows `#1234` alongside the contact name, inbox name, and snooze state

#### Scenario: clicking the ID copies it

- Given the conversation header shows `#1234`
- When the user clicks the `#1234` element
- Then `1234` is written to the clipboard
- And a success toast is shown

#### Scenario: clipboard failure is silent

- Given the clipboard API rejects the write
- When the user clicks the `#1234` element
- Then no error toast is shown and the header is unchanged
