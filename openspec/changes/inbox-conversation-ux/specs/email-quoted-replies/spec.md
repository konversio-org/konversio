## Capability: email-quoted-replies

Optionally append a quoted copy of the last incoming email to outbound email replies (upstream: `quotedEmailHelper.js`, `QuotedEmailPreview.vue`, ReplyBox integration).

---

## ADDED Requirements

### Requirement: Per-inbox quoted reply toggle

For email-channel inboxes, the reply editor SHALL offer a toggle controlling whether outbound replies quote the last incoming email. The preference MUST persist per channel type in UI settings.

#### Scenario: toggle visible only for email inboxes with quotable content

- Given a conversation in an email inbox whose last incoming message is an email
- Then the quoted-reply toggle is shown in the reply editor

- Given a conversation in a non-email inbox (e.g. web widget)
- Then the quoted-reply toggle is not shown

#### Scenario: preference persists per channel type

- Given the user enables quoted replies in an email inbox
- When the user reloads and opens another email conversation
- Then the toggle is still enabled
- And non-email channel types are unaffected

---

### Requirement: Quoted content composition

When enabled, the outbound email body MUST append: a header identifying the original sender (name and email, falling back through sender record → email metadata `from` → contact record) and the original date (from email metadata, falling back to message creation time), followed by the sanitized quoted body. The quoted text MUST be extracted from the last incoming email that has quotable content, with prior quote chains excluded so quotes do not nest.

#### Scenario: quote appended on send

- Given quoted replies are enabled and the last incoming email is from "Ada <ada@example.com>" on 2026-09-01
- When the agent sends a reply
- Then the outgoing message body ends with a quoted header naming the sender and date, followed by the sanitized original content

#### Scenario: HTML is sanitized before quoting

- Given the last incoming email contains HTML with script or unsafe markup
- When the quote is built
- Then the quoted content is sanitized (unsafe markup stripped) before being appended

#### Scenario: no nesting of earlier quotes

- Given the last incoming email itself contains a quoted reply chain
- When the quote is built
- Then only the newest (non-quoted) portion of that email is included

---

### Requirement: Quoted content preview

When the toggle is enabled, the reply editor SHALL show a dismissible preview of the quoted content, truncated to a short excerpt.

#### Scenario: preview reflects current quote

- Given quoted replies are enabled
- Then a preview above the editor shows the truncated quoted text

#### Scenario: clearing the conversation hides the preview

- Given the agent switches to a conversation without a quotable last incoming email
- Then neither toggle nor preview is shown
