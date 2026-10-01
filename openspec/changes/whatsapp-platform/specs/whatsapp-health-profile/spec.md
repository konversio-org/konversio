## Capability: whatsapp-health-profile

Persisted WhatsApp Business account health and business profile visibility: periodic/on-demand health sync stored on the channel, an inbox health API, and inbox-settings UI surfacing quality, limits, status, and profile information. All items in this capability are MIT ports of upstream core code.

---

## ADDED Requirements

### Requirement: Persisted phone-number health

The whatsapp_cloud channel SHALL persist a health snapshot (display phone number, verified name and its review status, quality rating, messaging limit tier, account status and mode, code verification status, throughput level, last-onboarded time, business-app and platform flags, and business account/portfolio identifiers and names) together with the time it was checked and any terminal error. Health API calls MUST use at least Graph API v24.0 regardless of the configured WhatsApp API version.

#### Scenario: health sync persists snapshot

- Given a whatsapp_cloud channel with valid credentials
- When health is synced
- Then the channel's health JSON, checked-at timestamp, and a cleared error are persisted

#### Scenario: partial failure preserves business identity fields

- Given a previously synced health snapshot
- When a re-sync succeeds for phone health but fails for the business account fetch
- Then the persisted snapshot merges the new phone health with the previously stored business account/portfolio fields

#### Scenario: total failure records error

- Given a channel whose credentials are rejected by the Graph API
- When health is synced
- Then the health error is recorded on the channel and the error is raised to the caller

#### Scenario: risky transitions are logged

- Given a channel whose quality rating or status transitions to a risky value (degraded quality, banned/restricted/rate-limited/flagged/disconnected/deleted)
- When the new snapshot is persisted
- Then a warning is logged with the transition details

---

### Requirement: Inbox health API

The inbox API SHALL expose `GET /api/v1/accounts/:account_id/inboxes/:id/health` for whatsapp_cloud inboxes, returning the freshly synced health snapshot (optionally including the business profile), and MUST surface provider errors in a structured form that distinguishes authorization failures from other API errors.

#### Scenario: health returned for cloud inbox

- Given a whatsapp_cloud inbox
- When health is requested
- Then the response contains the health fields and `health_checked_at`

#### Scenario: authorization error is distinguished

- Given a channel whose access token is expired
- When health is requested
- Then the response is unprocessable-entity with an error typed as an authorization failure, carrying the provider's code and message

#### Scenario: unsupported channel rejected

- Given a channel type without health support
- When health is requested
- Then the request fails with a bad-request error

---

### Requirement: Business profile visibility

For whatsapp_cloud inboxes the system SHALL fetch the WhatsApp Business profile (about, address, description, email, profile picture URL, websites, vertical) and include it in the health response when requested; profile unavailability MUST degrade gracefully to a logged warning and a nil profile rather than failing the health response.

#### Scenario: profile included in health response

- Given a whatsapp_cloud channel with a populated business profile
- When health is requested including the business profile
- Then the response contains a business profile section with the available fields

#### Scenario: profile fetch failure degrades gracefully

- Given the Graph API profile endpoint returns an error
- When health is requested including the business profile
- Then the health response succeeds without a business profile section
- And a warning with the provider error details is logged

---

### Requirement: Inbox settings health UI

The inbox settings UI SHALL surface account health for WhatsApp inboxes — quality rating, messaging limit, account status, verified name status, last checked time, and any recorded health error — and SHALL offer a refresh action; for whatsapp_cloud inboxes it SHALL also show the business profile section.

#### Scenario: health panel for cloud inbox

- Given a whatsapp_cloud inbox with synced health data
- When the user opens the inbox settings health area
- Then quality, limits, status, and last-checked time are displayed

#### Scenario: health error surfaced

- Given a channel with a recorded health error
- When the health area is viewed
- Then the error is shown with guidance to reauthorize or fix credentials

#### Scenario: clearer account health in setup (v4.18.0)

- Given a newly connected inbox from guided setup
- When the health area is viewed
- Then the current health state is visible without manual API calls
