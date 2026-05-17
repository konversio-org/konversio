## ADDED Requirements

### Requirement: Per-account auto-resolve configuration

Each account SHALL be able to configure Pilot auto-resolve through three settings stored in `account.pilot_autoresolve_config` JSONB: `enabled` (boolean), `idle_hours` (integer ≥ 1, default 24), `resolution_message` (string, default i18n key `pilot.autoresolve.default_message`). The configuration MUST also gate on the master `account.pilot_autoresolve_enabled` flag (separate from the JSONB so it can be indexed for scheduled job scans).

#### Scenario: Default-off for new accounts
- **WHEN** a new account is created
- **THEN** `pilot_autoresolve_enabled` is `false`
- **AND** the scheduler skips the account entirely

#### Scenario: Admin enables and configures
- **WHEN** an admin sets `pilot_autoresolve_enabled = true` AND `pilot_autoresolve_config = { idle_hours: 48 }`
- **THEN** the configuration is persisted
- **AND** the next scheduled scan considers this account

#### Scenario: idle_hours validation
- **WHEN** an admin attempts to set `idle_hours` to `0` or negative
- **THEN** the request is rejected with a 422 validation error

### Requirement: Eligibility criteria for auto-resolve

A conversation SHALL be eligible for auto-resolve only when ALL of the following are true:
- Its account has `pilot_autoresolve_enabled = true`
- Its status is `open` (not pending, not snoozed, not resolved)
- An Autopilot assistant is attached to its inbox AND has interacted with the conversation at least once (at least one message with `sender_type = Captain::Assistant`)
- The most recent inbound (customer) message is older than `idle_hours`
- No outbound message from a human agent occurred after the assistant's last interaction (handover-in-progress conversations are excluded)
- No prior auto-resolve attempt on this conversation has been recorded in the last `idle_hours` window (idempotency)

#### Scenario: Conversation matches all criteria
- **WHEN** a conversation has been idle 25 hours, last agent message was from the assistant, no human took over, account threshold is 24 hours
- **THEN** the conversation IS eligible

#### Scenario: Human took over after assistant
- **WHEN** the assistant replied, then a human agent replied, then the customer went idle
- **THEN** the conversation is NOT eligible (humans own this conversation)

#### Scenario: Conversation already resolved
- **WHEN** a conversation has status `resolved`
- **THEN** it is NOT eligible

#### Scenario: No assistant interaction
- **WHEN** the assistant never replied (the conversation reached the inbox but was handled entirely by humans)
- **THEN** the conversation is NOT eligible

### Requirement: Scheduled auto-resolve job

A `Pilot::AutoResolveJob` SHALL run hourly via Sidekiq-Cron (or equivalent scheduler). On each run it MUST scan all accounts with `pilot_autoresolve_enabled = true`, identify eligible conversations per the criteria above, and enqueue `Pilot::AutoResolveConversationJob` for each. The per-conversation job performs the actual resolve action.

#### Scenario: Hourly scan
- **WHEN** the scheduler fires `Pilot::AutoResolveJob`
- **THEN** the job queries accounts with the flag on
- **AND** for each account, runs the eligibility query against `Conversation` (using indexed columns to avoid full-table scans)
- **AND** enqueues per-conversation jobs on the `low` Sidekiq queue

#### Scenario: Per-conversation job resolves
- **WHEN** `Pilot::AutoResolveConversationJob` runs for a still-eligible conversation
- **THEN** an outgoing system message is posted with the configured `resolution_message`
- **AND** the conversation status is set to `resolved`
- **AND** a `pilot.autopilot.autoresolved` event is dispatched (see pilot-telemetry)
- **AND** a system note records "Auto-resolved by Pilot after N hours of inactivity"

#### Scenario: Race condition — human replied between scan and resolve
- **WHEN** the per-conversation job runs but eligibility check fails again (a human agent replied in the gap)
- **THEN** the job no-ops without resolving
- **AND** a debug log is recorded

### Requirement: Customer reopens the conversation

When a customer replies to an auto-resolved conversation, the existing Chatwoot reopen behavior SHALL run unchanged: status returns to `open` (or `pending` if Autopilot is attached and a fresh assistant inference runs). The conversation is then re-eligible for auto-resolve once it again satisfies all criteria.

#### Scenario: Customer reply reopens
- **WHEN** a customer sends a message to an auto-resolved conversation
- **THEN** the conversation reopens via the standard reopen flow
- **AND** if Autopilot is enabled, the new inference runs
- **AND** the next eligibility scan treats this as a fresh idle window

### Requirement: Auto-resolve respects business hours (optional)

When the inbox or account has business-hours configured, the idle window SHALL count only business hours, not wall-clock hours. An account with `idle_hours = 24` and business hours of 9-17 weekdays effectively means "after three business days," not "after 24 wall-clock hours." This requirement is OFF by default and MUST be opt-in via `pilot_autoresolve_config.respect_business_hours = true`.

#### Scenario: Business-hours mode
- **WHEN** an account has `respect_business_hours = true` AND `idle_hours = 24` AND business hours are weekdays 9-17 (8h/day)
- **THEN** a conversation that went idle Friday 16:00 is NOT eligible until Wednesday 16:00 (24 business hours)

#### Scenario: Default wall-clock mode
- **WHEN** `respect_business_hours` is unset or `false`
- **THEN** eligibility uses wall-clock hours

### Requirement: Admin can manually trigger auto-resolve scan

For testing and on-demand cleanup, admins SHALL be able to trigger the scan manually for their account via `POST /api/v2/accounts/:account_id/pilot/autoresolve/run_now`. The endpoint MUST be admin-only and MUST execute the same eligibility logic as the scheduled job, but synchronously for the caller's account only.

#### Scenario: Admin triggers run
- **WHEN** an admin POSTs to the endpoint
- **THEN** the eligibility scan runs immediately for that account
- **AND** the response includes `{ scanned: N, enqueued: M }` summary
- **AND** the per-conversation jobs are enqueued normally

#### Scenario: Non-admin forbidden
- **WHEN** a non-admin user POSTs to the endpoint
- **THEN** the response is `403`

### Requirement: Auto-resolve configuration UI

The Pilot settings SHALL expose an Auto-resolve panel visible when `account.pilot_autoresolve_enabled` is gated independently of the master `pilot_enabled` for safety (because auto-resolve is destructive to UX if misconfigured). The panel MUST display the current idle threshold, resolution message editor (with i18n preview), business-hours toggle, and a "Run now" button.

#### Scenario: Panel renders
- **WHEN** an admin opens Pilot → Auto-resolve settings
- **THEN** form fields for `enabled`, `idle_hours`, `resolution_message`, `respect_business_hours` are shown

#### Scenario: Resolution message preview
- **WHEN** the admin edits the resolution message
- **THEN** an inline preview renders the message as the customer would see it (template variables `{contact_name}`, `{assistant_name}` substituted with sample values)
