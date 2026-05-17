## ADDED Requirements

### Requirement: Pilot onboarding state per account

Each account SHALL track its Pilot onboarding progress through a `pilot_onboarding_state` JSONB column on `accounts` with the following keys: `provider_configured` (boolean), `assistant_created` (boolean), `inbox_attached` (boolean), `document_added` (boolean), `playground_tested` (boolean), `completed_at` (timestamp, nullable). The wizard renders steps based on these flags; completing all steps sets `completed_at`.

#### Scenario: New account has empty onboarding state
- **WHEN** an account first enables `pilot_enabled = true`
- **THEN** `pilot_onboarding_state` defaults to `{ provider_configured: false, assistant_created: false, inbox_attached: false, document_added: false, playground_tested: false, completed_at: null }`

#### Scenario: Onboarding completed
- **WHEN** all five step flags become `true`
- **THEN** `pilot_onboarding_state.completed_at` is set to the current timestamp
- **AND** the wizard UI no longer surfaces by default (admin can re-enter it via settings)

### Requirement: Provider configuration step with connection test

Step 1 of the wizard SHALL let the admin choose from a list of provider presets (Scaleway/EU default, Mistral La Plateforme, Nebius, Groq, OpenAI, Ollama, Custom) or paste a custom configuration. On submission, the wizard MUST perform a connection test (a single low-cost LLM call) and SHALL only mark the step complete when the test succeeds.

#### Scenario: Preset chosen and connection succeeds
- **WHEN** the admin selects "Scaleway (EU)" preset, enters their API key, and clicks "Test connection"
- **THEN** the wizard issues a small `RubyLLM.chat` test call with prompt "ping" using the resolved Pilot config
- **AND** on a 200 response, `pilot_onboarding_state.provider_configured` becomes `true`
- **AND** the API key is persisted via `GlobalConfigService` into `installation_configs` (DB row written)

#### Scenario: Connection test fails
- **WHEN** the test call raises an authentication error
- **THEN** the wizard displays the error message inline
- **AND** `provider_configured` remains `false`
- **AND** no DB write to `installation_configs` is performed

#### Scenario: Custom config bypasses preset
- **WHEN** the admin chooses "Custom" and enters `endpoint`, `model`, `api_key`, and toggles `openai_compatible`
- **THEN** the same connection test runs and the same persistence path applies

### Requirement: First assistant creation step

Step 2 SHALL guide the admin through creating their first `Captain::Assistant`. The form MUST require `name` and `description`, MAY pre-populate `config.product_name` from the account's name, and on save MUST create the assistant and set `pilot_onboarding_state.assistant_created = true`.

#### Scenario: Assistant created via wizard
- **WHEN** the admin submits the form with `name="Support Bot"` and `description="Answers product questions"`
- **THEN** a `Captain::Assistant` row is persisted with default `config`
- **AND** the step flag is set to `true`
- **AND** the wizard advances to the inbox step

### Requirement: Inbox attachment step

Step 3 SHALL let the admin pick one existing inbox from a dropdown and attach the just-created assistant to it. The wizard MUST validate that at least one Email or Website channel inbox exists before showing this step; if none exists, the wizard MUST link to inbox creation and resume after the user returns.

#### Scenario: Inbox attached
- **WHEN** the admin picks an inbox from the dropdown and submits
- **THEN** a `captain_inboxes` row is created
- **AND** `pilot_onboarding_state.inbox_attached` becomes `true`

#### Scenario: No inboxes exist
- **WHEN** the account has no Email or Website inboxes
- **THEN** the wizard displays a "Create your first inbox" link to the existing inbox creation flow
- **AND** the wizard step shows a "Skip for now" option

### Requirement: First document or scenario step

Step 4 SHALL let the admin populate the knowledge base in one of three ways: upload a PDF, paste a URL for Firecrawl/simple crawl, or add a scenario. The step is satisfied by any one of the three.

#### Scenario: PDF uploaded
- **WHEN** the admin uploads a valid PDF (<10 MB)
- **THEN** a `Captain::Document` row is created with auto-generated `external_link`
- **AND** `pilot_onboarding_state.document_added` becomes `true`

#### Scenario: URL added
- **WHEN** the admin pastes a URL
- **THEN** a `Captain::Document` row is created with that `external_link` and `CrawlJob` is enqueued
- **AND** the step flag becomes `true` (the document does not need to finish crawling for the step to complete)

#### Scenario: Scenario added instead
- **WHEN** the admin chooses "Add a scenario" and submits `{ title, instruction }`
- **THEN** a `Captain::Scenario` row is created
- **AND** the step flag becomes `true`

### Requirement: Playground test step

Step 5 SHALL surface the existing playground endpoint inline so the admin can send a test message and see the assistant's reply without leaving the wizard. Submitting at least one playground call MUST flip `pilot_onboarding_state.playground_tested = true`.

#### Scenario: Test message succeeds
- **WHEN** the admin types "Hello" and clicks "Test"
- **THEN** the playground POST executes and the reply renders inline
- **AND** the step flag becomes `true`
- **AND** the wizard advances to a completion screen

#### Scenario: Test call fails
- **WHEN** the playground call raises (provider unreachable, missing config)
- **THEN** the error is displayed inline
- **AND** the step flag remains `false` so the admin can fix and retry

### Requirement: Wizard surfacing rules

The wizard SHALL surface automatically on first visit to the dashboard when `account.pilot_enabled = true` AND `pilot_onboarding_state.completed_at IS NULL`. Admins MUST be able to dismiss it (sets a per-user dismissal flag, not the account state) and SHALL be able to re-enter it from Pilot settings at any time.

#### Scenario: First-time admin sees wizard
- **WHEN** an admin opens the dashboard for an account that just enabled Pilot
- **THEN** the wizard modal/page renders automatically

#### Scenario: Dismissed by user, not blocking team
- **WHEN** admin A dismisses the wizard
- **THEN** the wizard does not auto-surface for admin A again
- **AND** admin B (separate user in the same account) still sees the wizard

#### Scenario: Re-entry from settings
- **WHEN** an admin clicks "Pilot Setup Wizard" from Pilot settings
- **THEN** the wizard renders at the first incomplete step (or the welcome screen if `completed_at` is set)

### Requirement: Wizard works for already-configured operators

Operators who set `PILOT_OPEN_AI_*` env vars on the host before any admin opens the dashboard MUST see the provider step marked complete on first wizard surface. The connection test SHALL run on wizard open to verify the env-configured credentials still work, and the result populates `provider_configured` accordingly.

#### Scenario: Env-configured install skips provider entry
- **WHEN** the host has `PILOT_OPEN_AI_API_KEY` etc. set and the admin opens the wizard
- **THEN** the provider step shows "Detected: <model> at <endpoint>" with a "Re-test" button
- **AND** the connection test runs automatically; on success the step is marked complete and the wizard advances
