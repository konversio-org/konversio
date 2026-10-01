## Capability: whatsapp-account-health

A persisted WhatsApp phone-number health snapshot on cloud-API channels, refreshed by a scheduled sync and on demand from inbox settings, surfaced as a clear account-health view covering quality rating, status, messaging tier, display-name status, business profile, and webhook wiring. Reference implementation (MIT, verbatim port is legal): upstream `app/services/whatsapp/health_service.rb`, `app/jobs/channels/whatsapp/health_sync_job.rb`, `app/jobs/channels/whatsapp/health_sync_scheduler_job.rb`, `app/controllers/api/v1/accounts/concerns/inbox_health_management.rb`, `db/migrate/20260718000000_add_phone_number_health_to_channel_whatsapp.rb`, and `app/javascript/dashboard/routes/dashboard/settings/inbox/components/{AccountHealth,InboxHealthState}.vue`.

Scope note: this spec covers the v4.18.0 "clearer account health" surface. Broader WhatsApp health monitoring (v4.16.2) and business-profile visibility (v4.17.1) are tracked in the `voice-calling` and `whatsapp-platform` change dirs; requirements here are limited to what the account-health view and its sync pipeline need.

---

## ADDED Requirements

### Requirement: persisted health snapshot

WhatsApp channels SHALL persist a phone-number health snapshot (`phone_number_health`), the time it was last checked, and the last fetch error. Health persistence MUST bypass model validations and callbacks and MUST guard on the checked-at timestamp so a slower overlapping sync cannot overwrite a newer snapshot.

#### Scenario: successful sync persists the snapshot

- Given a WhatsApp Cloud API channel
- When a health sync completes successfully
- Then `phone_number_health` contains the phone fields (display number, verified name, name status, quality rating, messaging limit tier, status, account mode, verification status, throughput level, onboarding time, business-app and platform markers) and the business account fields (account and portfolio ids and names)
- And the checked-at timestamp is set to the sync attempt time
- And any previous fetch error is cleared

#### Scenario: partial failure retains previous business fields

- Given the phone-number fetch succeeds but the business-account fetch fails
- When the health sync persists
- Then the new phone fields are stored merged over the previously persisted business account fields
- And the fetch error message is recorded, truncated to at most 500 characters

#### Scenario: total failure records only the error

- Given both fetches fail
- When the health sync runs
- Then the previously persisted health snapshot is left intact
- And the checked-at timestamp and the truncated error message are recorded
- And the error is re-raised for the caller to handle

#### Scenario: stale sync cannot clobber a newer snapshot

- Given two concurrent syncs for the same channel attempt persistence
- When the sync with the older attempt time persists last
- Then it updates zero rows
- And the newer snapshot is preserved

### Requirement: risky transitions are logged

When a sync produces a snapshot whose quality rating or status indicates risk (a degraded quality rating, or a banned/restricted/rate-limited/flagged/disconnected/deleted status) and that risk signature differs from the previously persisted snapshot, the system SHALL emit a warning log with the account, inbox, channel, and the new rating/status values.

#### Scenario: transition into a risky state is logged once per change

- Given a channel whose persisted snapshot has a healthy quality rating
- When a sync returns a degraded rating
- Then a warning log is emitted identifying the channel and the new values
- And a subsequent sync with the same degraded values emits no further warning

### Requirement: scheduled health refresh

A scheduled low-priority job SHALL enqueue a per-channel health sync for WhatsApp Cloud API channels belonging to active accounts whose snapshot is stale (checked more than 6 hours ago or never), oldest first, bounded per run by the platform's bulk external HTTP call limit. The per-channel job MUST swallow provider API and validation errors so one failing channel never affects the rest.

#### Scenario: scheduler picks stale channels oldest-first

- Given three cloud-API channels with snapshots checked 10, 8, and 1 hours ago, and one embedded-signup-era non-cloud channel checked 12 hours ago
- When the scheduler runs
- Then sync jobs are enqueued for the 10-hour and 8-hour channels, oldest first
- And the 1-hour and non-cloud channels are skipped

#### Scenario: failing channel does not block others

- Given one channel's sync raises a provider API error
- When the per-channel job runs
- Then the error is swallowed
- And the remaining channels' jobs proceed normally

### Requirement: health endpoint with on-demand sync

The inbox `GET /api/v1/accounts/:account_id/inboxes/:id/health` endpoint SHALL, for WhatsApp Cloud API channels, perform an on-demand sync including the business profile and return the fresh snapshot with the checked-at timestamp; for unsupported channel types it SHALL return HTTP 400. Provider API errors SHALL return HTTP 422 with a structured error payload that distinguishes authorization failures (so the UI can prompt reauthorization) from other API errors.

#### Scenario: health returns fresh data with business profile

- Given a WhatsApp Cloud API inbox
- When health is requested
- Then a sync is performed and persisted
- And the response includes the phone and business fields, the business profile, the expected webhook URL for the channel, and the checked-at timestamp

#### Scenario: expired token yields an authorization error type

- Given the channel's access token is rejected by Meta as invalid/expired
- When health is requested
- Then the response is HTTP 422
- And the error payload's type is `authorization`

#### Scenario: unsupported channel type

- Given an email inbox
- When health is requested
- Then the response is HTTP 400

### Requirement: account health surface in inbox settings

The inbox settings for WhatsApp Cloud API channels SHALL present an account-health view showing: business identity (verified name or display number, profile picture, about, websites, and category when available), phone quality rating, phone status, messaging limit tier, display-name status with an explanatory description, account mode, throughput level, last onboarded time, and the health-checked timestamp — with color-coded severity for each value and a readable fallback for values without a known translation. The view SHALL show the expected webhook callback URL for the channel with a copy action and a one-click webhook re-registration action (administrators only), and SHALL prompt reauthorization when the health endpoint reports an authorization error.

#### Scenario: healthy channel renders green indicators

- Given a channel whose snapshot has a healthy quality rating, connected status, and live account mode
- When the account-health view renders
- Then those values display with positive (green) severity styling
- And the checked-at timestamp is formatted in the user's locale

#### Scenario: degraded values are visibly distinct

- Given a snapshot with a degraded quality rating and a restricted status
- When the account-health view renders
- Then the rating displays with warning (amber) severity and the status with danger (red) severity

#### Scenario: unknown values fall back gracefully

- Given a snapshot containing a status value with no known translation
- When the view renders
- Then the raw value is displayed in a humanized title-case form
- And the display-name status uses the unknown-state description

#### Scenario: webhook re-registration from the health view

- Given an administrator viewing account health for a channel whose Meta callback configuration is missing or mismatched
- When they invoke the register-webhook action
- Then the webhook registration endpoint is called for that inbox
- And the health data is refreshed afterwards

#### Scenario: authorization error prompts reauthorization

- Given the health endpoint returns an authorization-typed error
- When the account-health view renders
- Then a reauthorization prompt is shown instead of the health details
