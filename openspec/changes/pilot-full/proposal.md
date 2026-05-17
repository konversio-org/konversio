## Why

Konversio is an MIT-licensed fork of Chatwoot v4.13.0. The Enterprise edition (`enterprise/`) was stripped on legal grounds, taking with it the entire "Captain" AI feature surface (~9 controllers, ~7 models, ~32 services, ~25-30 Vue components). What remains is a working dashboard with hollowed-out AI menus, stub composables, and 15 orphaned `captain_*` database tables — but no AI capability for agents or end users.

Pilot is the replacement AI module: rebuilt as new Pilot code, but specified from the Captain behavior in the user's Enterprise fork plus the MIT `lib/captain/*` and `lib/llm/*` foundations that survived the strip. This proposal covers the full Pilot scope in a single change so the architecture stays coherent across all sub-features.

## What Changes

- **NEW** AI module umbrella called Pilot, namespaced under `Custom::Pilot::*` (services), `Api::V2::Accounts::Pilot::*` (controllers), and `components-next/pilot/*` (Vue).
- **NEW** provider-agnostic LLM foundation: env-first `PILOT_*` config via `GlobalConfigService`, OpenAI-compatible provider routing (Scaleway, Mistral, Nebius, Groq, Ollama), per-feature model overrides, configurable embedding dimensions, idempotent `/v1` endpoint handling. Scaleway + Mistral Small 3.2 24B is the EU-residency default.
- **NEW** Briefing sub-feature: one-click reply draft endpoint and composer button, wrapping the surviving MIT `lib/captain/reply_suggestion_service.rb`.
- **NEW** Copilot sub-feature: agent-side chat sidebar with asynchronous queued responses, backed by existing `copilot_threads`/`copilot_messages` migrations.
- **NEW** Autopilot sub-feature: customer-facing chatbot with assistants, documents, generated assistant responses/FAQs, scenarios, account-scoped custom tools, agent-bot pattern, and human-handover logic. Reuses existing `captain_*` migrations; rebuilds the Enterprise-deleted models, controllers, services, and UI as Pilot-owned code.
- **NEW** Logbook sub-feature: per-contact persistent memory extracted after conversation resolution; injected as context into Briefing, Copilot, and Autopilot. Introduces new `pilot_logbook_entries` table.
- **NEW** Tools sub-feature: pluggable HTTP tool framework for Autopilot, behavior-aligned with Captain custom tools but implemented as Pilot-owned code.
- **NEW** per-account `pilot_enabled` feature flag (gates all Pilot UI affordances).
- All Pilot env vars adopt the `PILOT_*` prefix. The user's `CAPTAIN_*` patches from `support.migrately.nl-upgrade` inform the design but are renamed in flight.

## Capabilities

### New Capabilities

- `pilot-foundation`: provider-agnostic LLM configuration, base service class, env-first/DB-fallback config precedence, OpenAI-compatible provider routing, embedding dimension control, per-feature model overrides, Agents SDK initialization. The shared substrate every other Pilot sub-feature depends on.
- `pilot-briefing`: one-click reply draft generation for agents from inside the conversation composer. Smallest sub-feature; first to ship end-to-end.
- `pilot-copilot`: agent-side conversational AI sidebar (threaded chat with the assistant about the current conversation, customer, or any agent question). Streaming responses, persistent thread history per agent.
- `pilot-autopilot`: customer-facing AI chatbot that answers from a curated knowledge base (`captain_documents` source records + vectorized `captain_assistant_responses`), with scenarios and handover behavior that route to a human agent when the assistant cannot answer.
- `pilot-logbook`: per-contact persistent memory layer. Extracts durable facts about a contact from resolved conversations and surfaces them as LLM context in subsequent interactions.
- `pilot-tools`: pluggable HTTP tool framework that lets an Autopilot assistant invoke external APIs (lookup orders, check status, etc.) during a customer chat. Tool results are injected back into the LLM context.
- `pilot-telemetry`: Pilot inference event taxonomy (briefing/copilot/autopilot/tool/logbook/handover lifecycle events) dispatched through Chatwoot's existing event dispatcher, with webhook + ActionCable broadcast, an activity log view, and sensitive-payload redaction.
- `pilot-onboarding`: first-time admin wizard for provider configuration (with live connection test), first assistant + inbox attachment + first document or scenario + playground test. Per-account onboarding state tracked in `accounts.pilot_onboarding_state` JSONB.
- `pilot-autoresolve`: scheduled job that auto-resolves conversations where an Autopilot assistant interacted and the customer has been idle past an account-configurable threshold (optionally counting business hours only). Mirrors Captain's `account_captain_auto_resolve` concern (already in the MIT tree) with explicit eligibility rules and a manual "Run now" admin endpoint.
- `pilot-utilities`: five small utility features wrapping the surviving MIT services in `lib/captain/`: conversation **Summary**, **CSAT** sentiment+theme analysis, **Follow-up** question suggestions, agent draft **Rewrite** with tone, and conversation **Label suggestion**. Each has its own per-account feature flag.

### Modified Capabilities

None. No prior Konversio spec defines AI behavior; this change introduces the capability surface from scratch.

## Impact

**Code added or rebuilt:**
- `custom/app/services/custom/pilot/**` — all new Pilot service classes (estimated ~25 files across sub-features).
- `app/controllers/api/v2/accounts/pilot/**` — ~16 new controllers (briefings, copilot_threads, copilot_messages, assistants, documents, scenarios, custom_tools, logbook_entries, preferences, playground, summaries, follow_ups, rewrites, onboarding, autoresolve, events/activity).
- `app/models/pilot/**` and resurrected `app/models/captain/**` — model classes for Captain::Assistant, Document, AssistantResponse, Scenario, CustomTool, CopilotThread, CopilotMessage, Pilot::LogbookEntry, plus any needed account associations.
- `app/javascript/dashboard/components-next/pilot/**` — ~30 Vue components across Briefing button, Copilot drawer, Autopilot management UI, Logbook viewer, Tools editor.
- `app/javascript/dashboard/store/pilot/**` — ~5 Vuex modules.
- `app/javascript/dashboard/api/pilot/**` — API client wrappers.
- `lib/llm/config.rb`, `lib/global_config_service.rb` — ported/extended with `PILOT_*` env handling.
- `config/initializers/ai_agents.rb` — updated agents SDK init in `after_initialize`.
- `db/migrate/*` — new `pilot_logbook_entries` table; new `pilot_events` table (telemetry persistence, 30-day retention); additive columns where current `captain_*` tables lack Captain behavior (for example assistant/tool config gaps); new account columns for `pilot_enabled`, the 6 sub-feature flags, the 5 utility-feature flags (`pilot_summary_enabled`, `pilot_csat_analysis_enabled`, `pilot_follow_up_enabled`, `pilot_rewrite_enabled`, `pilot_label_suggestion_enabled`), `pilot_autoresolve_enabled` + `pilot_autoresolve_config` JSONB, and `pilot_onboarding_state` JSONB.

**Code retained as-is (MIT, no edits):**
- `lib/captain/*` — 8 service files. Pilot wraps these; does not replace.
- `lib/llm/models.rb`, `lib/llm/exception_trackable.rb`.
- 15 existing `captain_*` migrations and tables. Table names stay (`captain_*`) per minimal-fork doctrine.
- `namespace :captain` routes (left mounted but unused; can be pruned in a later change).
- Stub composables `useCaptain.js`, `useCopilotReply.js`, `useLabelSuggestions.js` — superseded by new Pilot composables and deleted at end of this change.

**Enterprise Captain behavior used as OpenSpec input:**
- `enterprise/app/services/llm/base_ai_service.rb`
- `enterprise/app/services/captain/llm/*`
- `enterprise/app/models/captain/*`
- `enterprise/app/controllers/api/v1/accounts/captain/*`
- Adjacent Captain jobs/listeners/tool concerns may be read to clarify runtime behavior. Their behavior is translated into Pilot requirements; implementation should not preserve Enterprise-only billing or licensing gates.

**New env vars (set on Heroku app `konversio`):**
- `PILOT_OPEN_AI_API_KEY`, `PILOT_OPEN_AI_ENDPOINT`, `PILOT_OPEN_AI_MODEL`, `PILOT_OPEN_AI_API_PROVIDER`
- `PILOT_EMBEDDING_MODEL`, `PILOT_EMBEDDING_DIMENSIONS`
- `PILOT_OPEN_AI_TRANSLATION_MODEL`
- `PILOT_FIRECRAWL_API_KEY` (for Autopilot document ingestion)

**New external dependencies:**
- `ruby_llm` gem (provider routing)
- Existing `ai-agents` gem retained for multi-step agent loops; Pilot can use RubyLLM chat for v1-compatible assistant chat where simpler.
- `firecrawl` Ruby client (Autopilot document ingestion from URLs)

**API surface:**
- New namespace `/api/v2/accounts/:id/pilot/*` for all Pilot endpoints.
- No changes to existing public API contracts.

**Operational:**
- Sidekiq queue volume increases (embedding jobs for Autopilot document ingestion, memory-extraction jobs for Logbook on conversation resolution, hourly `Pilot::AutoResolveJob` scan + per-conversation resolve jobs, `Pilot::CsatAnalysisJob` on CSAT free-text, `Pilot::LabelSuggestionJob` on conversation create, `Pilot::EventsRetentionJob` daily). Current `SIDEKIQ_CONCURRENCY=5` on Heroku Eco worker is sized for low single-tenant volume; revisit before broader rollout.
- New scheduled jobs require sidekiq-cron or equivalent (already in Chatwoot stack).
- Postgres pgvector extension already in use; no new extensions required.
- New outbound HTTPS calls to the configured LLM provider. EU residency depends on the operator choosing an EU provider (Scaleway is the documented default).

**Not in scope (deferred to later changes):**
- Renaming `captain_*` tables to `pilot_*` (cosmetic; deferred).
- Removing the orphaned `namespace :captain` routes (cosmetic; deferred).
- Multi-account plan/usage billing for Pilot consumption (Enterprise-coupled feature; intentionally skipped under MIT).
- A Captain V1 / legacy single-turn code path. Pilot mirrors Captain V2 only (agentic loop, scenarios registered as handoff tools, structured tool calling via the ai-agents SDK). No `pilot_legacy_mode` flag, no dual code paths. See design.md D20 for rationale.
- Translating Pilot UI strings to non-English locales (per project i18n rule: only `en.yml` / `en.json` updated here).
