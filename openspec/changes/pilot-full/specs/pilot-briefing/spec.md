## ADDED Requirements

### Requirement: Briefing endpoint generates reply draft from conversation context

A `POST /api/v2/accounts/:account_id/pilot/briefings` endpoint SHALL accept a `conversation_id` and return a draft reply suitable for an agent to send. The endpoint MUST require an authenticated agent token, MUST verify the agent has access to the conversation, and MUST gate on `account.pilot_briefing_enabled`.

#### Scenario: Authenticated agent gets a draft
- **WHEN** an agent with access to conversation 42 POSTs `{"conversation_id": 42}` to `/api/v2/accounts/1/pilot/briefings` AND `pilot_briefing_enabled = true`
- **THEN** the response status is `200`
- **AND** the response body contains a `draft` field with the generated reply text

#### Scenario: Feature flag disabled
- **WHEN** an agent POSTs to the endpoint AND `pilot_briefing_enabled = false`
- **THEN** the response status is `403`

#### Scenario: Agent without conversation access
- **WHEN** an agent who is not a participant in conversation 42 POSTs `{"conversation_id": 42}`
- **THEN** the response status is `403`

#### Scenario: Missing conversation_id
- **WHEN** an agent POSTs an empty body
- **THEN** the response status is `400`

### Requirement: BriefingService wraps reply_suggestion_service

`Custom::Pilot::BriefingService` SHALL delegate the actual LLM call to the existing MIT `Captain::ReplySuggestionService`, passing the resolved Pilot model and provider configuration. The wrapper MUST add per-account feature gating, Pilot-namespaced telemetry, and (when Logbook is enabled) Logbook-context injection.

#### Scenario: Delegates to MIT captain service
- **WHEN** `BriefingService.new(conversation: c).perform`
- **THEN** `Captain::ReplySuggestionService` is instantiated with the Pilot-resolved model

#### Scenario: Logbook context injected when enabled
- **WHEN** `BriefingService` runs for a conversation whose contact has Logbook entries AND `pilot_logbook_enabled = true`
- **THEN** the prompt passed to the LLM includes the contact's Logbook entries as system context

#### Scenario: Logbook context skipped when disabled
- **WHEN** the same scenario but `pilot_logbook_enabled = false`
- **THEN** no Logbook content appears in the prompt

### Requirement: Composer Briefing button

The conversation composer UI SHALL render a "Get Briefing" button when `account.pilot_briefing_enabled` is `true`. Clicking the button MUST call the briefings endpoint, show a loading state, and populate the composer's draft area with the returned text.

#### Scenario: Button visible when flag is on
- **WHEN** the agent opens a conversation in an account with `pilot_briefing_enabled = true`
- **THEN** a "Get Briefing" button is visible in the composer toolbar

#### Scenario: Button absent when flag is off
- **WHEN** the agent opens a conversation in an account with `pilot_briefing_enabled = false`
- **THEN** no "Get Briefing" button is visible

#### Scenario: Clicking inserts draft
- **WHEN** the agent clicks "Get Briefing" AND the endpoint returns `{"draft": "Hi Alice, ..."}`
- **THEN** the composer textarea is populated with `"Hi Alice, ..."`
- **AND** the cursor is placed at the end of the inserted text

#### Scenario: Error state shown on failure
- **WHEN** the endpoint returns `500`
- **THEN** an inline error message is shown above the composer
- **AND** the composer textarea is left unchanged
