## Capability: account-resource-limits

Enforcement of the per-account inbox limit on every inbox creation path, with a shared limit-exception type and centralized HTTP 402 handling.

---

## ADDED Requirements

### Requirement: Inbox limit is enforced at the model level

Before an `Inbox` record is created, the system MUST verify that the account has fewer inboxes than `usage_limits[:inboxes]`. When the limit is reached, creation MUST raise `CustomExceptions::Inbox::LimitExceeded` and no inbox or channel record may be persisted. This guard applies to every creation path — the dashboard inbox form, channel OAuth/callback flows (Facebook, Instagram), telephony channel setup (Twilio), and WhatsApp signup — without per-controller configuration.

#### Scenario: inbox creation within limit succeeds

- Given an account with 2 inboxes and an inbox limit of 5
- When an admin creates an inbox through any creation path
- Then the inbox is created

#### Scenario: inbox creation at limit is rejected

- Given an account with 5 inboxes and an inbox limit of 5
- When an admin creates an inbox through the dashboard inbox form
- Then `CustomExceptions::Inbox::LimitExceeded` is raised
- And no inbox is created

#### Scenario: channel callback flow is covered

- Given an account at its inbox limit
- When an admin completes a Facebook page connection that would create a new inbox
- Then no channel or inbox record is persisted
- And the response is HTTP 402

---

### Requirement: Limit failures render a consistent 402 payload

`CustomExceptions::Inbox::LimitExceeded` MUST serialize as `{ "error": "<message>" }` with HTTP status 402 (Payment Required). Controllers whose actions wrap inbox creation in a broad error handler MUST rescue this exception explicitly and render its payload instead of a generic creation error.

#### Scenario: dashboard inbox create returns 402 payload

- Given an account at its inbox limit
- When an admin posts to `POST /api/v1/accounts/:account_id/inboxes`
- Then the response is HTTP 402
- And the body is a JSON object with an `error` key explaining the account limit was exceeded

#### Scenario: Twilio channel setup returns 402 instead of generic error

- Given an account at its inbox limit
- When an admin completes Twilio channel setup
- Then the response is HTTP 402 with the limit error payload
- And it is not rendered as a generic "could not create" error

#### Scenario: WhatsApp signup returns 402 instead of generic error

- Given an account at its inbox limit
- When an admin completes WhatsApp channel authorization that would create an inbox
- Then the response is HTTP 402 with the limit error payload

---

### Requirement: Limit exceptions are handled centrally

`RequestExceptionHandler` MUST register a `rescue_from` for `CustomExceptions::Inbox::LimitExceeded` and `CustomExceptions::Account::EmailLimitExceeded` that renders each exception's own payload and HTTP status, so any controller including the concern gets correct handling without local rescue code.

#### Scenario: unrescued limit exception is rendered by the concern

- Given a controller that includes `RequestExceptionHandler` and has no local rescue for limit exceptions
- When an action raises `CustomExceptions::Inbox::LimitExceeded`
- Then the response is HTTP 402 with the exception's error payload

#### Scenario: email limit exception renders 429

- Given a controller that includes `RequestExceptionHandler`
- When an action raises `CustomExceptions::Account::EmailLimitExceeded`
- Then the response is HTTP 429
- And the body contains a localized message that the account's daily email limit was reached

---

### Requirement: Per-account limits continue to resolve from the limits column

`usage_limits[:inboxes]` and `usage_limits[:agents]` MUST continue to honor per-account overrides stored in the account's `limits` jsonb column (as already implemented in the fork), falling back to the installation default maximum when no override is present. The Super Admin `limits` field remains the management surface for these values.

#### Scenario: override lowers the effective limit

- Given an account whose `limits` jsonb sets `inboxes` to 1
- And the account already has 1 inbox
- When an admin creates another inbox
- Then creation is rejected with `CustomExceptions::Inbox::LimitExceeded`

#### Scenario: no override falls back to the default maximum

- Given an account with an empty `limits` jsonb
- When `usage_limits` is read
- Then both `agents` and `inboxes` equal the installation default maximum
