## ADDED Requirements

### Requirement: Conversation summary endpoint

A `POST /api/v2/accounts/:account_id/pilot/summaries` endpoint SHALL accept a `conversation_id` and return a short LLM-generated summary of the conversation transcript suitable for handover notes or audit. The endpoint MUST gate on `account.pilot_summary_enabled` (new per-feature flag) and MUST require agent access to the conversation.

`Custom::Pilot::SummaryService` wraps the surviving MIT `Captain::SummaryService` and adds Pilot-namespaced config, Logbook context injection, and telemetry events.

#### Scenario: Agent requests summary
- **WHEN** an agent POSTs `{"conversation_id": 42}` AND `pilot_summary_enabled = true`
- **THEN** the response status is `200`
- **AND** the body contains `{ "summary": "<text>" }`

#### Scenario: Feature flag disabled
- **WHEN** `pilot_summary_enabled = false`
- **THEN** the response is `403`

#### Scenario: Summary button in conversation header
- **WHEN** an agent opens a conversation in an account with `pilot_summary_enabled = true`
- **THEN** a "Summarize" button appears in the conversation header/actions menu
- **AND** clicking it calls the summary endpoint and renders the result in a popover

### Requirement: Automatic CSAT sentiment analysis

When a customer responds to a CSAT survey with a free-text comment, a `Pilot::CsatAnalysisJob` SHALL be enqueued (gated on `account.pilot_csat_analysis_enabled`). The job calls the surviving MIT `Captain::CsatUtilityAnalysisService` and persists structured analysis on the CSAT response: `sentiment` (positive/neutral/negative), `themes` (string array), `escalation_recommended` (boolean).

The analysis MUST be stored alongside the `CsatSurveyResponse` so it appears in CSAT reports without an extra LLM call per page view.

#### Scenario: Free-text response triggers analysis
- **WHEN** a customer submits a CSAT survey with rating + comment "It took ages to get a refund"
- **THEN** `Pilot::CsatAnalysisJob` is enqueued on the `low` Sidekiq queue
- **AND** the job persists `sentiment: "negative"`, `themes: ["refund", "slow"]`, `escalation_recommended: true`

#### Scenario: Rating-only response skips analysis
- **WHEN** a customer submits a CSAT response with only a rating and no comment
- **THEN** no job is enqueued

#### Scenario: CSAT report shows themes
- **WHEN** an admin opens the CSAT report for a date range
- **THEN** an aggregated themes view shows the top 10 themes by frequency
- **AND** filterable by sentiment

### Requirement: Follow-up question suggestions

An agent SHALL be able to request follow-up question suggestions when a customer message is ambiguous or incomplete. A `POST /api/v2/accounts/:account_id/pilot/follow_ups` endpoint takes a `conversation_id` and returns 1-3 candidate clarifying questions. Gated on `account.pilot_follow_up_enabled`.

`Custom::Pilot::FollowUpService` wraps the surviving MIT `Captain::FollowUpService`.

#### Scenario: Agent requests suggestions
- **WHEN** an agent POSTs `{"conversation_id": 42}` AND `pilot_follow_up_enabled = true`
- **THEN** the response is `200` with `{ "suggestions": ["Could you tell me your order number?", "When did you place the order?"] }`

#### Scenario: Suggestions UI in composer
- **WHEN** the feature is enabled
- **THEN** a "Suggest follow-up" button appears next to the Briefing button in the composer
- **AND** clicking shows the suggestions as clickable chips that insert the chosen text into the composer

### Requirement: Rewrite agent draft with selected tone

An agent SHALL be able to select draft text in the composer and rewrite it via Pilot. A `POST /api/v2/accounts/:account_id/pilot/rewrites` endpoint takes `text` and `tone` (one of `friendly`, `formal`, `concise`, `empathetic`, `assertive`) and returns the rewritten text. Gated on `account.pilot_rewrite_enabled`.

`Custom::Pilot::RewriteService` wraps the surviving MIT `Captain::RewriteService`.

#### Scenario: Rewrite to friendlier tone
- **WHEN** an agent POSTs `{"text": "Refund denied.", "tone": "friendly"}`
- **THEN** the response is `200` with `{ "rewritten": "Unfortunately we're not able to issue a refund in this case, but let me explain why..." }`

#### Scenario: Invalid tone rejected
- **WHEN** the request includes `tone: "passive_aggressive"`
- **THEN** the response is `422` with a validation error listing allowed tones

#### Scenario: Composer "Rewrite" menu
- **WHEN** an agent selects text in the composer
- **THEN** a floating toolbar appears with a "Rewrite" button
- **AND** clicking opens a tone picker
- **AND** picking a tone calls the endpoint and replaces the selected text with the rewritten version

### Requirement: Conversation label suggestions

When a new conversation is created (or after an inbound customer message in an existing conversation), a `Pilot::LabelSuggestionJob` SHALL be enqueued (gated on `account.pilot_label_suggestion_enabled`). The job calls the surviving MIT `Captain::LabelSuggestionService` and stores suggested label ids on the conversation as `suggested_label_ids`. The agent UI presents these as one-click apply suggestions.

#### Scenario: New conversation triggers suggestions
- **WHEN** a conversation is created in an account with `pilot_label_suggestion_enabled = true`
- **THEN** `Pilot::LabelSuggestionJob` is enqueued
- **AND** the job persists `conversation.suggested_label_ids = [3, 7]` (subset of the account's existing labels)

#### Scenario: Agent applies suggested label
- **WHEN** an agent views a conversation with suggested labels
- **THEN** chips for each suggested label appear above the label selector
- **AND** clicking a chip applies the label (creates `ConversationLabel` row)
- **AND** removes the chip from the suggested list

#### Scenario: Suggestions are non-destructive
- **WHEN** a label is suggested but the agent does not apply it
- **THEN** the conversation is not automatically labeled
- **AND** suggestions clear when the conversation is resolved

### Requirement: Utility services share the per-feature flag pattern

All five utilities (summary, CSAT analysis, follow-up, rewrite, label suggestion) SHALL each have their own per-account boolean flag column following the established Pilot pattern (`pilot_summary_enabled`, `pilot_csat_analysis_enabled`, `pilot_follow_up_enabled`, `pilot_rewrite_enabled`, `pilot_label_suggestion_enabled`). All default to `false` and require `account.pilot_enabled = true` to take effect.

#### Scenario: Per-feature gating
- **WHEN** `pilot_enabled = true` AND `pilot_summary_enabled = true` AND `pilot_rewrite_enabled = false`
- **THEN** the Summary endpoint returns 200
- **AND** the Rewrite endpoint returns 403

#### Scenario: Master gate overrides
- **WHEN** `pilot_enabled = false` AND any per-feature flag is `true`
- **THEN** all utility endpoints return 403
