## Context

Konversio inherited a half-empty AI surface from the Chatwoot strip: `lib/captain/*` services and `lib/llm/*` config survived (MIT), 15 `captain_*` migrations still create their tables on `db:prepare`, the `namespace :captain` routes remain mounted, and three stub composables sit in the Vue layer returning permanently-disabled state. Everything between those layers — controllers, models, services, Vue components, Vuex modules — was Enterprise-only and has been deleted from the working tree.

The user owns a parallel Chatwoot Enterprise install (`/Users/rcoenen/Dev/Migrately/support.migrately.nl-upgrade`) that contains the Captain implementation Pilot is replacing. For this OpenSpec pass, those Enterprise files are an allowed behavior reference: read them to extract product behavior, data contracts, and runtime flow, then express that behavior as fresh Pilot requirements and implementation tasks.

This change rebuilds the missing layers from behavior specs informed by that Captain source. The aim is a coherent Pilot module that ships useful AI to Konversio operators, keeps new code under Pilot names, and adapts the implementation to Konversio's current MIT tree.

## Captain Source Reference

**Konversio MIT sources to reuse directly:**
- `/Users/rcoenen/Dev/Konversio/lib/captain/**`
- `/Users/rcoenen/Dev/Konversio/lib/llm/**`
- `/Users/rcoenen/Dev/Konversio/db/migrate/*captain*`
- `/Users/rcoenen/Dev/Konversio/db/migrate/*copilot*`
- `/Users/rcoenen/Dev/Konversio/config/routes.rb`

**Enterprise Captain sources to read as behavior reference and translate into Pilot:**
- `/Users/rcoenen/Dev/Migrately/support.migrately.nl-upgrade/enterprise/app/services/llm/base_ai_service.rb`
- `/Users/rcoenen/Dev/Migrately/support.migrately.nl-upgrade/enterprise/app/services/captain/llm/**`
- `/Users/rcoenen/Dev/Migrately/support.migrately.nl-upgrade/enterprise/app/models/captain/**`
- `/Users/rcoenen/Dev/Migrately/support.migrately.nl-upgrade/enterprise/app/controllers/api/v1/accounts/captain/**`
- Adjacent runtime flow files may be read when needed to understand behavior: `enterprise/app/listeners/captain_listener.rb`, `enterprise/app/jobs/captain/**`, and tool helper concerns. Do not keep Enterprise names in new public Pilot APIs unless the database table already uses a `captain_*` name.

## Goals / Non-Goals

**Goals:**
- A complete MIT-licensed AI module covering one-click reply drafts (Briefing), agent-side conversational AI (Copilot), customer-facing chatbots with knowledge bases (Autopilot), per-contact persistent memory (Logbook), a pluggable tool framework (Tools), inference-event telemetry (Telemetry), first-time admin setup (Onboarding), idle-conversation auto-resolve (Auto-resolve), and a set of small utility features wrapping the surviving MIT services (Utilities: summary, CSAT analysis, follow-up suggestions, draft rewrite, label suggestion).
- Full behavioral parity with Chatwoot Enterprise Captain for everything that isn't billing/licensing — the operator who runs Konversio with a configured LLM provider gets the same AI surface they'd get from a paid Chatwoot Enterprise install, minus the usage-tracking telemetry that Captain reports to chatwoot.com.
- Env-first configuration: an operator who sets `PILOT_OPEN_AI_API_KEY` + `PILOT_OPEN_AI_ENDPOINT` + `PILOT_OPEN_AI_MODEL` on the host should get a working Pilot install with no manual DB configuration required. `GlobalConfigService` may auto-write effective ENV values to `installation_configs` for admin visibility.
- Provider-agnostic LLM routing: any OpenAI-compatible endpoint (Scaleway, Mistral, Nebius, Groq, Ollama, Azure OpenAI) works out of the box. The OpenAI-proper SaaS is one option among many, not the default.
- EU residency by recommendation: Scaleway hosting Mistral Small 3.2 24B is the documented default (validated at ~0.5s LLM round-trip in the user's other fork).
- Reuse the surviving MIT `lib/captain/*` services as the actual LLM-task implementations; Pilot services are thin wrappers that add config/feature-flag/event-dispatch concerns around them.
- Coherent naming: every new symbol carries `Pilot` (services, controllers, components, env vars). The `captain_*` legacy names survive only in tables and the unused routes namespace, both per minimal-fork doctrine.

**Non-Goals:**
- Renaming `captain_*` database tables or migrating their data.
- Removing the orphaned `namespace :captain` routes.
- Reaching parity with Chatwoot Enterprise's billing/usage-tracking surface.
- Translating Pilot UI to non-English locales (project i18n rule: English-only here).
- Multi-tenant per-account billing limits on Pilot consumption.
- Reporting Pilot usage to a vendor telemetry endpoint (Pilot's own event stream is local-only; what gets sent off-host is entirely the operator's webhook configuration).
- Implementing a Captain V1 / legacy-mode code path. Pilot is V2-only (agentic, scenarios-as-tools); see D20.

## Decisions

### D1 — Mega-proposal instead of per-sub-feature proposals

We capture all six capabilities in one OpenSpec change. **Why:** the sub-features share a foundation (Llm::Config, Pilot::BaseService, env-var conventions, provider routing) and ship as one coherent product; splitting risks fragmenting that foundation across proposals or shipping a half-built foundation. **Alternative considered:** one foundation proposal + five sub-feature proposals (Option A in the structural decision). Rejected on user preference for a single archive.

### D2 — Behavior port, not code copy

Pilot controllers, models, services, and Vue components are written as fresh Pilot code, but the Enterprise Captain files are read to capture behavior: associations, validations, endpoints, async jobs, prompt responsibilities, and UI contracts. **Why:** the user explicitly wants the OpenSpec to mirror the Captain product before building Pilot. **Alternative considered:** pure clean-room reconstruction from memory and surviving MIT files. Rejected because it already produced mismatches such as document chunks instead of assistant responses, assistant-scoped custom tools instead of account-scoped tools, and streaming Copilot instead of queued persisted replies.

### D3 — `Custom::Pilot::*` namespace under `custom/`

All new Pilot services live in `custom/app/services/custom/pilot/`. **Why:** matches the handoff doc's locked file layout; keeps Pilot easy to vendor out of upstream Chatwoot rebases (the `custom/` tree is convention-reserved for fork-specific code). **Alternative considered:** `app/services/pilot/` directly. Rejected because future Chatwoot upstream rebases would conflict with that path.

### D4 — Wrap `lib/captain/*`, do not replace

`Custom::Pilot::BriefingService` instantiates and calls `Captain::ReplySuggestionService` (the surviving MIT service). The Pilot wrapper adds feature-flag gating, install-wide provider config, Logbook context injection, and Pilot-namespaced telemetry. **Why:** the captain services are working code, already MIT, already aware of `Llm::Config`; rewriting them buys nothing and risks regressions. **Alternative considered:** copy each captain service into `Custom::Pilot::*` and modify. Rejected — duplicative, drift-prone.

### D5 — Env-first config via `GlobalConfigService`

Every Pilot setting is read through `GlobalConfigService.load(key, default)`, which checks ENV first, then the `installation_configs` DB row, and writes back to DB on first ENV-only read so the admin UI shows the effective value. **Why:** Heroku-style deployments want env vars; on-prem operators want a UI; both must work. The user's patches on the other fork already validated this pattern. **Alternative considered:** ENV-only, no DB. Rejected — admin UI cannot display or override values. **Alternative considered:** DB-only with seed. Rejected — operators want to rotate keys without a Rails console.

### D6 — `PILOT_OPEN_AI_API_PROVIDER=openai_compatible` for non-OpenAI providers

When this env is set, `Llm::Config.model_options` returns `{ provider: 'openai', assume_model_exists: true }`, bypassing the RubyLLM model registry. **Why:** RubyLLM whitelists known OpenAI models and rejects unknown model strings; setting `assume_model_exists` lets the same code path call Scaleway's `mistral-small-3.2-24b-instruct-2506`, Groq's `llama-3.1-70b-versatile`, an Ollama model, etc. **Alternative considered:** maintain our own model registry. Rejected — duplicates RubyLLM's job and keeps drifting as new models appear.

### D7 — `openai_use_system_role=true` always set when configuring RubyLLM

Non-OpenAI providers reject the `developer` role that newer OpenAI models accept; they expect classic `system/user/assistant/tool`. Setting this on every `RubyLLM.configure` block keeps the same code working on both. **Why:** the user's patches verified this is the smallest cross-provider compatibility shim. **Alternative considered:** conditionally set based on provider. Rejected — adds a branch with no upside; OpenAI itself still accepts `system`.

### D8 — Embedding dimensions controlled in service layer

`pgvector` columns stay at 1536 dimensions. The embedding service passes a `dimensions` parameter to the provider (OpenAI text-embedding-3-small supports server-side truncation; other providers may natively return 1536). **Why:** lets operators swap embedding providers without a migration. The native-768 or native-4096 model still produces a 1536-dim vector that fits the existing column. **Alternative considered:** variable-dimension pgvector columns. Rejected — requires per-account migrations and column rewrites; not worth it for v1.

### D9 — Idempotent `/v1` endpoint suffix

Pilot config strips a trailing `/v1` from `PILOT_OPEN_AI_ENDPOINT` before appending its own `/v1` in code paths that need it (the agents SDK expects the base endpoint shape used by its config; RubyLLM expects `/v1` included). **Why:** operators paste the endpoint URL from provider docs; some docs include `/v1`, some don't. Failing on the wrong suffix is a terrible first-run UX. The user's patches already encode this.

### D10 — AI agents SDK initialised in `after_initialize`

The existing `ai-agents` gem requires the API key and base URL at construction. Since `GlobalConfigService` reads from `installation_configs`, which requires the DB, init must happen after Rails finishes booting. Done by updating `config/initializers/ai_agents.rb` with `Rails.application.config.after_initialize { ... }`. **Why:** the user's patches discovered this the hard way during the other fork's setup. **Alternative considered:** lazy init on first call. Rejected — adds a per-request branch and obscures startup failures.

### D11 — Logbook is opt-in per account, extraction runs after `Conversation#resolved!`

A new `Pilot::LogbookExtractionJob` enqueues from a `Conversation` after-update callback when the conversation transitions to `resolved` AND the account has `pilot_logbook_enabled`. The job calls an LLM to extract durable contact facts from the conversation transcript, dedupes against existing `pilot_logbook_entries` for that contact, inserts new entries. **Why:** post-resolution is when the conversation is complete and stable; running during the chat risks extracting fleeting state. **Alternative considered:** real-time extraction on every customer message. Rejected — expensive, noisy, and gives the customer no chance to refine their statement.

### D12 — Tools framework runs synchronously inside the inference loop

Captain custom tools are account-scoped records with generated `custom_*` slugs, `endpoint_url`, `request_template`, `response_template`, `auth_type`, `auth_config`, and an array-style `param_schema`. Pilot keeps that data shape and matches Captain's runtime model: the tool HTTP call executes **synchronously** inside the same job/request as the LLM call — the agent loop suspends, the HTTP fires in-process, and the loop resumes with the tool result. Pilot adds stricter SSRF, response truncation (8 KB), structured error codes returned to the LLM, and instrumentation spans. **Why:** Captain integrates `Captain::Tools::CustomHttpTool` directly into the inference; an async Sidekiq design would require suspending/resuming the agent across processes, which neither RubyLLM nor the ai-agents SDK supports natively. **Alternative considered:** async execution via `Pilot::ToolExecutionJob`. Rejected because Captain doesn't work that way and the spec drift would force a custom suspended-agent state machine.

### D13 — Vue layer under `components-next/pilot/`

All new Pilot UI lives under `app/javascript/dashboard/components-next/pilot/`. Per CLAUDE.md, `components-next/` is the only sanctioned subtree for new components (the rest is being deprecated). Existing dashboard code that hosts Pilot affordances (the conversation composer, the message list, the conversation header) gets minimal-diff edits to import and conditionally render Pilot components based on `pilot_enabled`.

### D14 — Per-account `pilot_enabled` feature flag

Added as a column on `accounts` (default `false`) plus a per-feature column for each sub-capability: `pilot_briefing_enabled`, `pilot_copilot_enabled`, `pilot_autopilot_enabled`, `pilot_logbook_enabled`, `pilot_tools_enabled`, `pilot_autoresolve_enabled`, plus the five Utilities flags (`pilot_summary_enabled`, `pilot_csat_analysis_enabled`, `pilot_follow_up_enabled`, `pilot_rewrite_enabled`, `pilot_label_suggestion_enabled`). All default `false`. UI gates render entirely off these flags; API endpoints return 403 when the relevant flag is off. **Why:** lets operators roll out sub-features independently; matches Chatwoot's existing `account_features` flag pattern but is explicit columns rather than a JSON blob (faster reads in hot paths like message composer). **Alternative considered:** single `pilot_enabled` flag. Rejected — coarser-grained than operators will want; Logbook and Auto-resolve in particular are privacy- or UX-sensitive features that some accounts will never enable.

### D15 — EU-residency provider default

Documentation and the Provider Presets initializer suggest Scaleway + Mistral Small 3.2 24B (endpoint `https://api.scaleway.ai/v1`, model `mistral-small-3.2-24b-instruct-2506`). **Why:** validated end-to-end in the user's other fork at ~0.5s LLM round-trip with fluent Dutch responses; Scaleway is an EU-based provider, satisfying GDPR data-residency by default. **No code defaults to this** — operators must set the env vars. The docs and Onboarding wizard recommend it.

### D16 — Telemetry uses Chatwoot's existing dispatcher + webhook + ActionCable

Pilot inference events use `Rails.configuration.dispatcher.dispatch(...)` (the same dispatcher Chatwoot uses for `conversation_created` and friends) instead of a new event bus. **Why:** webhooks, ActionCable broadcasts, and admin event-subscription UI already work for this dispatcher; reusing it means operators get Pilot events on their existing webhook infrastructure with no new transport. **Alternative considered:** a separate `Pilot::EventStream` with its own subscribers. Rejected — duplicate machinery, more docs to write, no concrete benefit.

A persisted `pilot_events` table is added for the in-dashboard Activity view (event dispatchers are fire-and-forget by default; the dashboard needs a queryable history). Retention defaults to 30 days, purged by `Pilot::EventsRetentionJob`. **Alternative considered:** reuse `audit_logs`. Rejected — `audit_logs` is schemaed for user-attributed mutations; Pilot events are system-emitted with different fields.

### D17 — Auto-resolve is opt-in per account with explicit eligibility rules

`Pilot::AutoResolveJob` runs hourly under sidekiq-cron, scans accounts with `pilot_autoresolve_enabled = true`, and applies six explicit eligibility rules before resolving a conversation: open status, assistant attached AND has interacted, customer idle past threshold, no human-agent message after the last assistant message, no recent auto-resolve attempt on this conversation, business-hours-aware countdown when configured. **Why:** auto-resolve is destructive to UX if misconfigured. Captain's existing `account_captain_auto_resolve.rb` concern surfaces in the MIT codebase but doesn't express these rules as testable predicates — Pilot lifts them to explicit specs so every condition has a scenario. **Alternative considered:** simpler "resolve if idle > N hours, period" rule. Rejected — would resolve handovers in progress, conversations where humans were just slow to reply, and re-resolve already-resolved conversations.

### D18 — Onboarding state is per-account JSONB, dismissal is per-user

`pilot_onboarding_state` is a single JSONB column on `accounts` tracking the five wizard steps and a `completed_at`. Per-user dismissal of the auto-surface modal is a separate per-user preference. **Why:** the onboarding state is a property of the install (the team's progress), but whether *this admin* wants to see the wizard popping up is personal. **Alternative considered:** account-level dismissal. Rejected — dismissing for the team would hide setup-blocking guidance from a new admin who joins later.

### D19 — Utilities reuse MIT services without duplication

The five Utilities (Summary, CSAT, Follow-up, Rewrite, Label suggestion) each wrap an existing `lib/captain/*` service rather than duplicating it. The Pilot wrapper adds feature-flag gating, telemetry events, and Logbook context injection. **Why:** the MIT services are already proven and minimal; rebuilding them gains nothing. **Alternative considered:** new `Custom::Pilot::SummaryService` etc. that re-implement the LLM prompts. Rejected as gratuitous churn.

### D20 — Pilot is Captain V2 only; no V1/legacy mode

Chatwoot Enterprise Captain ships two LLM code paths gated by the `captain_integration_v2` feature flag: V1 (single-turn `RubyLLM.chat`, sentinel-string handover) and V2 (agentic loop via the ai-agents SDK, scenarios registered as callable handoff tools, structured tool calling). Pilot SHALL implement only the V2 behavior. There is no `pilot_legacy_mode` flag, no V1 fallback path, no dual code paths inside any Pilot service. **Why:**
- V2 is upstream's direction; V1 is being phased out behind the feature flag.
- V2 is a strict superset of V1 — every V1 use case (cost control, latency, models without tool calling) is tunable inside V2 (cap `max_agent_steps`, pick a cheaper per-feature model, skip tool registration for a given assistant).
- Two code paths double maintenance, test surface, and bug-fix cost forever.

**Alternative considered:** Ship Pilot with a `pilot_legacy_mode` per-account flag that bypasses the agent loop. Rejected — no validated demand, and adding it later is purely additive if a customer ever asks. Removing it later is much harder.

**Implication for the agent loop:** `Custom::Pilot::AutopilotService` and `Custom::Pilot::CopilotService` go directly through the ai-agents SDK's runner pattern (mirroring `Captain::Assistant::AgentRunnerService`). They do NOT first try a single-turn RubyLLM call and "upgrade" to the agent loop on tool detection.

## Risks / Trade-offs

- **Scope risk: this is a large change.** ~10 controllers, ~8 models, ~25 services, ~30 Vue components in a single proposal. → **Mitigation:** sub-features build sequentially within the task list; each is independently shippable to staging. Foundation + Briefing alone is a usable v1; later sub-features can be merged in subsequent commits before final archive.
- **Behavior-port risk: copying Enterprise implementation instead of translating behavior.** → **Mitigation:** Enterprise Captain files are used to extract contracts and runtime flow, but new code remains Pilot-namespaced and adapted to Konversio's current tables, dependencies, and feature flags.
- **Provider compatibility risk: third-party OpenAI-compatible providers drift.** Scaleway/Mistral/Nebius can change tokenizer behavior, role-handling, or function-calling semantics at any time. → **Mitigation:** the test suite mocks at the RubyLLM boundary; integration smoke tests for each documented preset run as part of `bundle exec rspec spec/services/custom/pilot/integration/`; CI does not call live LLMs.
- **Embedding-dim mismatch risk: a provider returns the wrong vector size.** → **Mitigation:** EmbeddingService asserts `vector.length == 1536` before insert; logs a warn-level error with the configured `PILOT_EMBEDDING_DIMENSIONS` if it mismatches; raises in dev/test, no-ops the insert in prod (logged for review). Migrating columns to other dims is out of scope.
- **Sidekiq queue saturation: Logbook extraction + Autopilot document response generation both queue jobs.** Heroku Eco worker with `SIDEKIQ_CONCURRENCY=5` cannot absorb a high message volume. → **Mitigation:** new `low` queue for `LogbookExtractionJob`, document response generation, and embedding refresh jobs; Sidekiq config prioritizes the existing queues; `_KONVERSIO/HANDOFF.md` followups already flag Redis upgrade as a separate item.
- **Tools SSRF risk: HTTP tools could be used to scan internal IPs.** → **Mitigation:** outbound URL goes through safe endpoint validation and optional account/assistant host allowlisting; private RFC1918 and link-local ranges are denied at the connection layer; tool config UI avoids wildcard hosts.
- **First-run UX risk: new admins won't know which env vars to set.** → **Mitigation:** ship `PILOT_PRESETS.md` (similar to user's `CAPTAIN_PRESETS.md`) with copy-paste-ready configurations for Scaleway, Mistral, Nebius, Groq, OpenAI, Ollama; link from Super Admin → Pilot Setup.
- **Vue-side regression risk: importing Pilot components into the composer/message-list breaks existing dashboard for non-Pilot accounts.** → **Mitigation:** all Pilot UI is mounted behind `pilot_*_enabled` v-if gates; lazy-import via `defineAsyncComponent` so JS bundles don't grow for accounts with Pilot disabled.

## Migration Plan

This is an additive change with no destructive migrations. Rollout sequence:

1. **DB migrations** (forward-only):
   - Add `pilot_enabled` + 5 per-feature boolean columns to `accounts` (default `false`).
   - Add `pilot_logbook_entries` table.
   - Add indexes on `pilot_logbook_entries(contact_id, created_at)` and on `accounts(pilot_enabled) WHERE pilot_enabled`.

2. **Backend deploy** (no behavior change — all gated on `pilot_*_enabled = false`):
   - Ship Foundation, then Briefing, then Copilot, then Autopilot, then Logbook, then Tools as the task list orders them. Each sub-feature can ship to production with its account flag still off.

3. **Frontend deploy** in the same release as each backend sub-feature.

4. **Env-var provisioning** on Heroku (one-time per install):
   ```
   heroku config:set -a konversio \
     PILOT_OPEN_AI_API_KEY=... \
     PILOT_OPEN_AI_ENDPOINT=https://api.scaleway.ai/v1 \
     PILOT_OPEN_AI_MODEL=mistral-small-3.2-24b-instruct-2506 \
     PILOT_OPEN_AI_API_PROVIDER=openai_compatible \
     PILOT_EMBEDDING_MODEL=bge-multilingual-gemma2 \
     PILOT_EMBEDDING_DIMENSIONS=1536
   ```

5. **Enable per account** via Super Admin → Accounts → Edit:
   - First Migrately's own customer-zero account (`Account.find(1)`).
   - Enable Briefing first, observe a week, then Copilot, then progressively the rest.

**Rollback:** flip `pilot_enabled = false` on the affected account; UI disappears. Code stays deployed. If a code-level rollback is needed, the pre-Pilot commit on `main` is the rollback target — every Pilot change is additive, so reverting is a clean `git revert`.

## Open Questions

1. **Agents SDK vs. RubyLLM assistant chat** — Enterprise Captain supports both a RubyLLM chat path and an agents runner path behind a feature flag. **Default decision:** Pilot v1 implements the RubyLLM-compatible assistant chat path first and keeps the existing `ai-agents` initializer ready for a multi-step runner once needed.
2. **Logbook entry retention** — do entries expire? Per-contact cap? **Default decision:** no automatic expiry in v1; soft cap of 100 entries per contact enforced at extraction time (drop oldest). Revisit when storage cost matters.
3. **Streaming transport for Copilot** — SSE vs. ActionCable vs. polling persisted messages? **Default decision:** match Captain first: queued response job + persisted assistant message + UI pending state. Add ActionCable token streaming later if the product needs it.
4. **Per-account provider overrides** — should an account be able to override the install-wide `PILOT_OPEN_AI_*` env? **Default decision:** v1 ships install-wide only; per-account override is a v2 capability. Architecturally `GlobalConfigService` already supports per-key DB rows, so this is a UI/data-model add later, not a refactor.
5. **Document ingestion file size limits** — Autopilot lets users upload PDFs/URLs. What's the cap? **Default decision:** 10 MB per file, 100 documents per assistant, 50 MB total per account. Configurable via `PILOT_DOC_*` envs in v2.
