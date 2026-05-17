## ADDED Requirements

### Requirement: Pilot inference event taxonomy

Pilot SHALL dispatch a named event for every observable Pilot action through Chatwoot's existing `Rails.configuration.dispatcher`. The event taxonomy is fixed and namespaced under `pilot.*`. Event payloads MUST include a stable schema so external consumers can rely on field names across releases.

Event names:
- `pilot.briefing.started`, `pilot.briefing.completed`, `pilot.briefing.failed`
- `pilot.copilot.message.created`, `pilot.copilot.inference.started`, `pilot.copilot.inference.completed`, `pilot.copilot.inference.failed`
- `pilot.autopilot.inference.started`, `pilot.autopilot.inference.completed`, `pilot.autopilot.inference.failed`
- `pilot.autopilot.handover.triggered` (with `reason` field: `low_confidence` | `customer_requested` | `scenario_match` | `llm_requested`)
- `pilot.autopilot.document.crawled`, `pilot.autopilot.document.responses_generated`
- `pilot.logbook.extraction.started`, `pilot.logbook.extraction.completed`, `pilot.logbook.entry.created`, `pilot.logbook.entry.deleted`
- `pilot.tool.invoked`, `pilot.tool.completed`, `pilot.tool.failed`

#### Scenario: Briefing event lifecycle
- **WHEN** an agent triggers a Briefing
- **THEN** `pilot.briefing.started` is dispatched at the start of the BriefingService call
- **AND** `pilot.briefing.completed` is dispatched on successful generation with `{ account_id, conversation_id, agent_id, model, duration_ms }`
- **AND** if the LLM call raises, `pilot.briefing.failed` is dispatched with `{ account_id, conversation_id, agent_id, model, error_class, error_message }` instead of `completed`

#### Scenario: Tool invocation event
- **WHEN** the Autopilot inference loop invokes a custom tool
- **THEN** `pilot.tool.invoked` is dispatched with `{ account_id, assistant_id, tool_slug, conversation_id }`
- **AND** either `pilot.tool.completed` (with `duration_ms`, `http_status`) OR `pilot.tool.failed` (with `error_code`) is dispatched after execution

#### Scenario: Handover event includes reason
- **WHEN** Autopilot hands a conversation over to a human
- **THEN** `pilot.autopilot.handover.triggered` is dispatched
- **AND** the payload's `reason` is one of `low_confidence`, `customer_requested`, `scenario_match`, `llm_requested`

### Requirement: Webhook subscriptions for Pilot events

Operators SHALL be able to subscribe to Pilot events through Chatwoot's existing Webhook resource by selecting Pilot event names in the webhook configuration. When a subscribed event fires, the webhook MUST POST the event payload to the configured URL with HMAC signature using the webhook's secret.

#### Scenario: Webhook receives subscribed event
- **WHEN** an admin configures a webhook subscribed to `pilot.briefing.completed`
- **AND** a Briefing completes for an account that owns the webhook
- **THEN** the webhook URL receives a POST with the event payload
- **AND** the request includes the standard Chatwoot HMAC `X-Chatwoot-Signature` header

#### Scenario: Unsubscribed events do not fire webhooks
- **WHEN** an admin configures a webhook subscribed only to `pilot.briefing.completed`
- **AND** a Copilot inference completes
- **THEN** the webhook URL receives no request for the Copilot event

#### Scenario: Webhook UI lists Pilot events
- **WHEN** an admin opens the webhook configuration form
- **THEN** the event picker includes all `pilot.*` event names grouped under a "Pilot" section
- **AND** events for disabled sub-features (per account flag) are hidden from the picker

### Requirement: ActionCable broadcast for dashboard subscribers

Pilot events SHALL also broadcast to a per-account ActionCable channel `PilotEventsChannel` so the dashboard can render live activity (e.g., "Autopilot replied to 3 conversations in the last minute"). The broadcast payload MUST match the webhook payload exactly so a single consumer implementation works for both transports.

#### Scenario: Dashboard receives event
- **WHEN** a subscribed dashboard client is connected to `PilotEventsChannel` for account 1
- **AND** an Autopilot inference completes in account 1
- **THEN** the channel emits a `pilot.autopilot.inference.completed` message with the standard payload

#### Scenario: Cross-account isolation
- **WHEN** a client subscribed to account 1's channel exists
- **AND** an event fires in account 2
- **THEN** the account-1 channel receives no message

### Requirement: Activity log view

The dashboard SHALL provide a Pilot Activity view per account that lists recent Pilot events in reverse-chronological order. The view MUST support filtering by event name prefix (`pilot.briefing.*`, `pilot.autopilot.*`, etc.) and by date range. Events MUST be persisted for a minimum retention window of 30 days for this view to function; persistence MAY use either the `audit_logs` table (if compatible) or a new `pilot_events` table.

#### Scenario: View shows recent events
- **WHEN** an admin opens the Pilot Activity view
- **THEN** events from the last 30 days are listed in reverse-chronological order
- **AND** each row shows event name, timestamp, related entities (conversation_id, assistant_id, agent_id where applicable), and outcome (success/failure)

#### Scenario: Filter by event prefix
- **WHEN** the admin filters by `pilot.tool.*`
- **THEN** only tool-related events appear

#### Scenario: Retention enforcement
- **WHEN** an event is older than the configured retention window (default 30 days)
- **THEN** a `Pilot::EventsRetentionJob` SHALL purge it on the next run

### Requirement: Sensitive payload redaction

Event payloads SHALL NOT contain raw customer message bodies, tool auth headers, or LLM prompts. Such fields MUST be redacted to length + checksum (e.g., `{ "prompt_length": 1240, "prompt_sha256": "abc..." }`) so events remain useful for observability without leaking PII or secrets.

#### Scenario: Briefing prompt is redacted
- **WHEN** `pilot.briefing.completed` is dispatched
- **THEN** the payload does NOT include the LLM prompt text
- **AND** it includes `prompt_length` and `prompt_sha256` metadata

#### Scenario: Tool auth header is redacted
- **WHEN** `pilot.tool.invoked` is dispatched
- **THEN** the payload does NOT include the value of any auth header
- **AND** it includes a list of auth-header names that were sent
