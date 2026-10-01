## Capability: webhook-platform

Webhook payload enrichment, account-level gating of API-token access and webhook delivery, Slack inbound webhook signature verification, and an alerts-only (one-way) mode for the Slack integration.

---

## ADDED Requirements

### Requirement: Inbox lifecycle webhooks embed an account summary

The `inbox_created` and `inbox_updated` webhook payloads MUST be built from a dedicated webhook presenter that merges the inbox push data with an account summary (`id`, `name`).

#### Scenario: inbox_created payload includes account

- Given an account webhook subscribed to `inbox_created`
- When an inbox is created
- Then the delivered payload contains the event name, the inbox configuration data, and an `account` object with `id` and `name`

#### Scenario: inbox_updated payload includes changed attributes

- Given an account webhook subscribed to `inbox_updated`
- When an inbox attribute changes
- Then the payload contains the changed attributes and the account summary

---

### Requirement: Account-level gate for API-token access and webhook delivery

The system SHALL provide an account-level check that determines whether API-token access and outbound webhook delivery are enabled. The check MUST return disabled when the account is suspended and enabled otherwise. Enforcement points MUST reject token-authenticated API requests with HTTP 403 and skip account webhook delivery when the gate is disabled.

#### Scenario: active account passes the gate

- Given an active account
- When an API request is made with a valid access token
- Then the request proceeds normally

#### Scenario: suspended account is rejected on token-authenticated endpoints

- Given a suspended account
- When an API request is made with a valid access token for that account
- Then the response is HTTP 403 with an error indicating API access is not enabled

#### Scenario: suspended account receives no webhook deliveries

- Given a suspended account with configured account webhooks
- When a subscribed event fires
- Then no webhook delivery is attempted for that account

#### Scenario: direct uploads are gated

- Given a suspended account
- When an authenticated direct-upload request is made for a conversation
- Then the response is HTTP 403

---

### Requirement: Slack inbound webhook requests are signature-verified when a secret is configured

When `SLACK_SIGNING_SECRET` is configured, inbound Slack integration webhook requests MUST be rejected with HTTP 401 unless they carry a timestamp header within a 5-minute tolerance and a signature header equal to `v0=` followed by the hex HMAC-SHA256 of the string `v0:<timestamp>:` concatenated with the raw request body, compared in constant time. When no secret is configured, verification MUST be skipped with a warning log so existing installations keep working.

#### Scenario: valid signature is accepted

- Given `SLACK_SIGNING_SECRET` is configured
- When a Slack webhook request arrives with a current timestamp and a correctly computed signature
- Then the request is processed

#### Scenario: invalid signature is rejected

- Given `SLACK_SIGNING_SECRET` is configured
- When a request arrives with a mismatched signature
- Then the response is HTTP 401 and no message processing occurs

#### Scenario: stale timestamp is rejected

- Given `SLACK_SIGNING_SECRET` is configured
- When a request arrives with a timestamp 10 minutes old and an otherwise valid signature
- Then the response is HTTP 401

#### Scenario: missing secret skips verification

- Given `SLACK_SIGNING_SECRET` is not configured
- When any Slack webhook request arrives
- Then the request is processed and a warning is logged

---

### Requirement: Slack integration supports an alerts-only mode

A Slack integration hook SHALL support a message-mode setting. In alerts-only mode the integration is one-way: conversation content is pushed to Slack, but messages posted in Slack MUST NOT be synced into Konversio conversations.

#### Scenario: alert mode drops inbound Slack messages

- Given a Slack hook configured with alerts-only mode
- When a reply is posted in the linked Slack thread
- Then no message is created in the Konversio conversation

#### Scenario: two-way mode syncs inbound messages

- Given a Slack hook not in alerts-only mode
- When a reply is posted in the linked Slack thread
- Then the message appears in the Konversio conversation

#### Scenario: outbound push still works in alert mode

- Given a Slack hook in alerts-only mode
- When an agent sends a message in the linked conversation
- Then the message is pushed to Slack
