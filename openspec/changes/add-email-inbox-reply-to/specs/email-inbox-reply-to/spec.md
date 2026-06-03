## Capability: email-inbox-reply-to

Configurable Reply-To address per email inbox, surfaced in inbox settings and applied to all outbound replies.

---

## ADDED Requirements

### Requirement: reply_to_email stored on Channel::Email

Email inbox records SHALL store an optional `reply_to_email` address representing the public-facing address contacts should reply to, which MAY differ from the internal `email` catch address.

#### Scenario: reply_to_email is nil by default

- Given a new email inbox is created
- Then `channel.reply_to_email` is nil
- And outbound replies use `channel.email` as the Reply-To header

#### Scenario: reply_to_email can be set and updated via API

- Given an email inbox exists
- When the inbox is updated with `reply_to_email: "support@example.com"`
- Then `channel.reply_to_email` equals `"support@example.com"`

#### Scenario: reply_to_email is exposed in the inbox API response

- Given an email inbox has `reply_to_email` set
- When the inbox is fetched via `GET /api/v1/accounts/:id/inboxes`
- Then the response includes `reply_to_email`

---

### Requirement: Email::ReplyToBuilder uses reply_to_email when present

When an email inbox has `reply_to_email` set, outbound reply emails MUST carry that value as the `Reply-To` header instead of `channel.email`.

#### Scenario: reply_to_email present — used as Reply-To

- Given an email inbox with `email: "mail@support.example.com"` and `reply_to_email: "support@example.com"`
- When `Email::ReplyToBuilder#build` is called
- Then the result contains `"support@example.com"`

#### Scenario: reply_to_email absent — falls back to channel.email

- Given an email inbox with `email: "mail@support.example.com"` and `reply_to_email: nil`
- When `Email::ReplyToBuilder#build` is called
- Then the result contains `"mail@support.example.com"`

---

### Requirement: Reply-To address field in email inbox settings UI

The email inbox settings page MUST expose an optional "Reply-To address" input field that reads and writes `reply_to_email`.

#### Scenario: field is visible for email inboxes only

- Given the user opens inbox settings for an email inbox
- Then a "Reply-To address" input field is visible
- And it is pre-populated with the current `reply_to_email` value (or empty)

#### Scenario: saving updates reply_to_email

- Given the user enters "support@example.com" in the Reply-To address field
- When the user saves settings
- Then the inbox API is called with `reply_to_email: "support@example.com"`
- And subsequent outbound replies carry `Reply-To: support@example.com`

#### Scenario: clearing the field removes the override

- Given an email inbox has `reply_to_email` set
- When the user clears the field and saves
- Then `reply_to_email` is nil
- And outbound replies revert to using `channel.email` as Reply-To
