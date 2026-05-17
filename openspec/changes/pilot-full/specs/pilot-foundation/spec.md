## ADDED Requirements

### Requirement: Env-first configuration precedence

Pilot configuration values SHALL be resolved through `GlobalConfigService.load(key, default)`, which MUST check the process environment first, fall back to the `installation_configs` database table, and write back any ENV-only value to the DB on first read so the admin UI surfaces the effective value.

#### Scenario: ENV value overrides DB value
- **WHEN** `PILOT_OPEN_AI_API_KEY=env_key` is set in the environment AND an `installation_configs` row exists with `name=PILOT_OPEN_AI_API_KEY, value=db_key`
- **THEN** `GlobalConfigService.load('PILOT_OPEN_AI_API_KEY', nil)` returns `env_key`

#### Scenario: DB fallback when ENV unset
- **WHEN** `PILOT_OPEN_AI_API_KEY` is not set in the environment AND `installation_configs` has `name=PILOT_OPEN_AI_API_KEY, value=db_key`
- **THEN** `GlobalConfigService.load('PILOT_OPEN_AI_API_KEY', nil)` returns `db_key`

#### Scenario: Auto-writeback on first ENV read
- **WHEN** `PILOT_OPEN_AI_MODEL=mistral-small` is set in the environment AND no `installation_configs` row exists for that key
- **THEN** first call to `GlobalConfigService.load('PILOT_OPEN_AI_MODEL', nil)` returns `mistral-small`
- **AND** an `installation_configs` row is created with `name=PILOT_OPEN_AI_MODEL, value=mistral-small`

#### Scenario: Default returned when neither ENV nor DB has value
- **WHEN** no ENV and no DB row exists for `PILOT_OPEN_AI_MODEL`
- **THEN** `GlobalConfigService.load('PILOT_OPEN_AI_MODEL', 'gpt-4o-mini')` returns `gpt-4o-mini`

### Requirement: OpenAI-compatible provider routing

Pilot SHALL accept any OpenAI-compatible LLM endpoint by setting `PILOT_OPEN_AI_API_PROVIDER=openai_compatible`. When this flag is set, the LLM configuration MUST pass `{ provider: 'openai', assume_model_exists: true }` to RubyLLM so unknown model names are not rejected by the registry.

#### Scenario: Native OpenAI provider
- **WHEN** `PILOT_OPEN_AI_API_PROVIDER` is unset or equals `openai` AND `PILOT_OPEN_AI_MODEL=gpt-4o-mini`
- **THEN** `Llm::Config.model_options('reply_suggestion')` returns `{ provider: 'openai', model: 'gpt-4o-mini' }`

#### Scenario: OpenAI-compatible provider
- **WHEN** `PILOT_OPEN_AI_API_PROVIDER=openai_compatible` AND `PILOT_OPEN_AI_MODEL=mistral-small-3.2-24b-instruct-2506`
- **THEN** `Llm::Config.model_options('reply_suggestion')` returns `{ provider: 'openai', model: 'mistral-small-3.2-24b-instruct-2506', assume_model_exists: true }`

#### Scenario: RubyLLM accepts the compatible config
- **WHEN** an OpenAI-compatible config is passed to a `RubyLLM.chat` invocation
- **THEN** no `RubyLLM::ModelNotFoundError` is raised even if the model name is unknown to RubyLLM's registry

### Requirement: System role compatibility for non-OpenAI providers

Every `RubyLLM.configure` call inside Pilot SHALL set `openai_use_system_role = true` so non-OpenAI providers that reject the newer `developer` role still accept the message stream.

#### Scenario: Configuration includes the system-role flag
- **WHEN** `Llm::Config.configure_ruby_llm` is invoked
- **THEN** the resulting configuration sets `openai_use_system_role` to `true`

### Requirement: Idempotent /v1 endpoint suffix handling

When the operator supplies `PILOT_OPEN_AI_ENDPOINT`, Pilot SHALL strip a trailing `/v1` before storing or passing the value, and SHALL re-append `/v1` only in code paths that require it (RubyLLM expects `/v1` in the URL; the agents SDK uses the base endpoint shape from its configuration).

#### Scenario: Endpoint with trailing /v1
- **WHEN** `PILOT_OPEN_AI_ENDPOINT=https://api.scaleway.ai/v1`
- **THEN** `Llm::Config.api_base` returns `https://api.scaleway.ai`
- **AND** RubyLLM's effective base URL is `https://api.scaleway.ai/v1`

#### Scenario: Endpoint without trailing /v1
- **WHEN** `PILOT_OPEN_AI_ENDPOINT=https://api.scaleway.ai`
- **THEN** `Llm::Config.api_base` returns `https://api.scaleway.ai`
- **AND** RubyLLM's effective base URL is `https://api.scaleway.ai/v1`

### Requirement: Per-feature model overrides

Pilot SHALL support per-feature model overrides via environment variables of the form `PILOT_OPEN_AI_<FEATURE>_MODEL`. When the per-feature override is unset, the default `PILOT_OPEN_AI_MODEL` is used.

#### Scenario: Translation model overrides default
- **WHEN** `PILOT_OPEN_AI_MODEL=gpt-4o` AND `PILOT_OPEN_AI_TRANSLATION_MODEL=mistral-small`
- **THEN** `Llm::Config.model_for('translation')` returns `mistral-small`
- **AND** `Llm::Config.model_for('reply_suggestion')` returns `gpt-4o`

### Requirement: Embedding dimension control

Pilot SHALL allow the operator to configure the embedding output dimension via `PILOT_EMBEDDING_DIMENSIONS`. The embedding service MUST pass this dimension to the provider for server-side truncation, and MUST assert that the returned vector has length 1536 before inserting into the pgvector column.

#### Scenario: Dimension passed to provider
- **WHEN** `PILOT_EMBEDDING_DIMENSIONS=1536` AND the embedding service receives a text input
- **THEN** the provider API call includes `dimensions: 1536` in the request body

#### Scenario: Dimension mismatch raises in development
- **WHEN** the provider returns a vector of length 768 in a development environment
- **THEN** the embedding service raises `Pilot::EmbeddingDimensionMismatchError`

#### Scenario: Dimension mismatch warns and skips in production
- **WHEN** the provider returns a vector of length 768 in a production environment
- **THEN** the embedding service logs a warning AND skips the insert AND returns `nil`

### Requirement: Pilot base service class

A `Custom::Pilot::BaseService` class SHALL be the common parent for all Pilot sub-feature services. It MUST expose helpers for: resolving the configured LLM model for a given feature, instantiating a `RubyLLM.chat` context with the correct system-role flag, dispatching Pilot telemetry events, and checking per-account `pilot_<feature>_enabled` flags.

#### Scenario: Subclass inherits config helpers
- **WHEN** a `Custom::Pilot::BriefingService` extends `Custom::Pilot::BaseService` AND invokes `model_for('briefing')`
- **THEN** the resolved model is the result of `Llm::Config.model_for('briefing')`

#### Scenario: Feature flag gate
- **WHEN** an account has `pilot_briefing_enabled = false`
- **THEN** `Custom::Pilot::BaseService#feature_enabled?(:briefing)` returns `false` for that account

### Requirement: Per-account feature flags

The `accounts` table SHALL gain six boolean columns, all defaulting to `false`: `pilot_enabled`, `pilot_briefing_enabled`, `pilot_copilot_enabled`, `pilot_autopilot_enabled`, `pilot_logbook_enabled`, `pilot_tools_enabled`. Pilot UI affordances MUST be rendered only when the relevant column is `true`.

#### Scenario: Default-off for new accounts
- **WHEN** a new `Account` is created
- **THEN** `account.pilot_enabled` is `false`
- **AND** `account.pilot_briefing_enabled` is `false`

#### Scenario: Master flag gates everything
- **WHEN** an account has `pilot_briefing_enabled = true` AND `pilot_enabled = false`
- **THEN** the Briefing UI does not render
- **AND** the `POST /api/v2/accounts/:id/pilot/briefings` endpoint returns `403`

### Requirement: AI agents initialised after Rails boot

When the existing `ai-agents` SDK is used by any Pilot sub-feature, its configuration MUST be applied inside `Rails.application.config.after_initialize` so that `GlobalConfigService` (which reads `installation_configs` from the DB) is available.

#### Scenario: Init runs after Rails boots
- **WHEN** Rails finishes booting
- **THEN** the agents SDK has been configured with `api_key`, `api_base`, and `model` resolved through `GlobalConfigService`

#### Scenario: No Agents SDK init at require-time
- **WHEN** the Pilot initializer is required during eager-loading
- **THEN** no DB query is issued

### Requirement: Config namespace isolation from Captain

Pilot configuration keys SHALL use the `PILOT_*` prefix exclusively and MUST NOT read, write, or fall back to `CAPTAIN_*` keys. An operator who has both prefixes set (because they also run Enterprise Captain elsewhere) gets independent configurations: Pilot services consult only `PILOT_*` keys, and any legacy `CAPTAIN_*` keys are ignored by Pilot.

#### Scenario: Both prefixes present
- **WHEN** the process environment contains both `CAPTAIN_OPEN_AI_API_KEY=captain_key` and `PILOT_OPEN_AI_API_KEY=pilot_key`
- **THEN** `Llm::Config.api_key` returns `pilot_key`
- **AND** no Pilot code path reads `CAPTAIN_OPEN_AI_API_KEY`

#### Scenario: Only legacy CAPTAIN_* present
- **WHEN** the process environment contains only `CAPTAIN_OPEN_AI_API_KEY` and no `PILOT_OPEN_AI_API_KEY`
- **THEN** Pilot treats `PILOT_OPEN_AI_API_KEY` as unset (falls back to DB, then to the documented default)
- **AND** Pilot does NOT silently inherit the Captain key

### Requirement: Provider presets documentation

A `PILOT_PRESETS.md` document SHALL ship in the repo with copy-paste-ready environment-variable configurations for at minimum: Scaleway, Mistral La Plateforme, Nebius, Groq, OpenAI, and Ollama. The document MUST document Scaleway + Mistral Small 3.2 24B as the recommended EU-residency default.

#### Scenario: Presets file exists at repo root
- **WHEN** the repo is checked out at `main`
- **THEN** `PILOT_PRESETS.md` exists at the project root
- **AND** it contains a section titled "Scaleway (EU-residency default)"
