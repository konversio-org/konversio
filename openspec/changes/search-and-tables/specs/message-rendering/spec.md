## Capability: message-rendering

Conversation message rendering gains a dedicated bubble for `fallback`-type attachments, overflow-safe bubble layout, and removal of dead legacy template bubble components.

---

## ADDED Requirements

### Requirement: fallback attachments SHALL render as a titled link bubble

A message whose single attachment is of type `fallback` MUST render a dedicated bubble showing the attachment's fallback title (falling back to the URL when no title exists) as a link to the attachment URL, opening in a new tab. When the message also has text content, the formatted content MUST render above the link.

#### Scenario: fallback attachment renders as link

- Given a message with a single `fallback` attachment with title "Order #1234" and a URL
- When the message renders in a conversation
- Then the bubble shows "Order #1234" as a link to the URL that opens in a new tab

#### Scenario: missing title falls back to the URL

- Given a message with a single `fallback` attachment with no title and a URL
- Then the bubble shows the URL text itself as the link label

#### Scenario: content renders above the link

- Given a message with text content and a single `fallback` attachment
- Then the formatted message text renders above the attachment link in the same bubble

---

### Requirement: fallback-type attachments SHALL be classified as non-file types

The message constants MUST classify `location`, `fallback`, and `contact` attachment types as non-file types, so file-oriented UI (gallery views, download affordances) excludes them.

#### Scenario: fallback attachment excluded from file handling

- Given UI logic that lists file attachments of a conversation
- When it encounters a `fallback` attachment
- Then the attachment is not treated as a downloadable file

---

### Requirement: message bubbles SHALL NOT overflow on long unbroken content

The message bubble grid area and the base bubble MUST allow shrinking below content width (`min-w-0`) so long unbroken strings truncate or wrap instead of overflowing the conversation panel.

#### Scenario: long URL does not overflow the bubble

- Given an incoming message containing a 500-character unbroken URL
- When the message renders in a narrow conversation panel
- Then the bubble stays within the panel width and no horizontal overflow occurs

---

### Requirement: legacy template bubble components SHALL be removed

The dead `bubbles/Template/*` components and their stories MUST be deleted; template messages MUST render through the standard text bubble.

#### Scenario: template message renders via text bubble

- Given a message of template message type with text content
- When the message renders
- Then it uses the standard text bubble rendering path
- And no `bubbles/Template` components exist in the codebase
