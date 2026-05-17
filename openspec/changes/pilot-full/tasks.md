## 1. Foundation — schema and config plumbing

- [ ] 1.1 Verify existing `Gemfile` dependencies (`ruby_llm`, `ai-agents`) and add the `firecrawl` gem if URL ingestion needs the Ruby client; run `bundle install`
- [ ] 1.2 Create migration adding `pilot_enabled`, `pilot_briefing_enabled`, `pilot_copilot_enabled`, `pilot_autopilot_enabled`, `pilot_logbook_enabled`, `pilot_tools_enabled` boolean columns (default `false`) to `accounts`
- [ ] 1.3 Add partial index on `accounts(id) WHERE pilot_enabled`
- [ ] 1.4 Create `lib/global_config_service.rb` (env-first → DB fallback → auto-writeback) if it does not already exist in the Konversio tree
- [ ] 1.5 Port/create `lib/llm/config.rb`: `model_for(feature)`, `model_options(feature)`, `api_base`, `configure_ruby_llm`, `with_api_key`. Honor `PILOT_OPEN_AI_API_PROVIDER=openai_compatible`. Always set `openai_use_system_role=true`. Idempotent `/v1` stripping.
- [ ] 1.6 Update `lib/llm/models.rb` (or `config/llm.yml`) feature→model registry to default to Pilot feature names
- [ ] 1.7 Update existing `config/initializers/ai_agents.rb` to resolve `PILOT_*` config through `GlobalConfigService` inside `Rails.application.config.after_initialize`
- [ ] 1.8 Create `custom/app/services/custom/pilot/base_service.rb` with helpers: `model_for`, `feature_enabled?`, `chat_context`, `dispatch_event`
- [ ] 1.9 Add `Pilot::EmbeddingDimensionMismatchError` exception class
- [ ] 1.10 Create `custom/app/services/custom/pilot/embedding_service.rb` (Pilot adaptation of Captain embedding behavior; pass `dimensions` to provider; assert returned vector length is 1536; raise in dev/test, warn+nil in prod on mismatch)
- [ ] 1.11 Author `PILOT_PRESETS.md` at repo root with Scaleway (default), Mistral La Plateforme, Nebius, Groq, OpenAI, Ollama copy-paste blocks
- [ ] 1.12 Update `_KONVERSIO/HANDOFF.md` env-var section: replace `PILOT_*` placeholder list with the now-real env-var contract
- [ ] 1.13 Write rspec coverage for `Llm::Config` (env-first precedence, openai_compatible flag, system-role flag, /v1 idempotency, `CAPTAIN_*` namespace isolation — Pilot never reads CAPTAIN keys)
- [ ] 1.14 Write rspec coverage for `Custom::Pilot::BaseService` (feature gate, model resolution)

## 2. Briefing — endpoint + composer button

- [ ] 2.1 Create `Custom::Pilot::BriefingService` (extends `BaseService`); delegate to `Captain::ReplySuggestionService`; optional Logbook context injection
- [ ] 2.2 Add route `POST /api/v2/accounts/:account_id/pilot/briefings` under a new `Api::V2::Accounts::Pilot` namespace
- [ ] 2.3 Create `Api::V2::Accounts::Pilot::BriefingsController#create` with: auth, account-flag gate, conversation-access check, error handling (400/403/500)
- [ ] 2.4 Add Pundit policy `Pilot::BriefingPolicy` (agent must be participant on conversation)
- [ ] 2.5 Create Vue composable `useBriefing.js` under `app/javascript/dashboard/composables/pilot/` (calls the briefings endpoint, manages loading/error state)
- [ ] 2.6 Create `BriefingButton.vue` under `app/javascript/dashboard/components-next/pilot/briefing/`; render only when `pilot_briefing_enabled`; loading + error states
- [ ] 2.7 Mount `BriefingButton.vue` in the existing composer toolbar via minimal-diff edit; lazy-import via `defineAsyncComponent`
- [ ] 2.8 Add i18n strings to `en.json`: `PILOT.BRIEFING.BUTTON_LABEL`, `PILOT.BRIEFING.LOADING`, `PILOT.BRIEFING.ERROR`
- [ ] 2.9 Write rspec for `BriefingsController` (200, 403 on flag off, 403 on no access, 400 on missing param)
- [ ] 2.10 Write rspec for `Custom::Pilot::BriefingService` (delegates to ReplySuggestionService; injects Logbook when enabled; skips when not)
- [ ] 2.11 Run `bundle exec rails assets:precompile` locally — verify Vite picks up the new components without errors

## 3. Copilot — backend models, async replies, drawer UI

- [ ] 3.1 Rebuild `Captain::CopilotThread` model under `app/models/captain/copilot_thread.rb` (backed by existing `copilot_threads`; belongs_to account, user/agent, assistant; has_many copilot_messages)
- [ ] 3.2 Rebuild `Captain::CopilotMessage` model (backed by existing `copilot_messages`; belongs_to thread/account; `message_type` integer enum `user=0`, `assistant=1`, `assistant_thinking=2`; JSON `message` payload with content; enqueue response job helper; dispatch `COPILOT_MESSAGE_CREATED` event on create)
- [ ] 3.3 Add routes for `copilot_threads` (index, create) and nested `copilot_messages` (index, create) under the Pilot namespace
- [ ] 3.4 Create `Api::V2::Accounts::Pilot::CopilotThreadsController` (CRUD; agent-scoped; 404 on cross-agent access)
- [ ] 3.5 Create `Api::V2::Accounts::Pilot::CopilotMessagesController#create` (persists user message; enqueues `Pilot::CopilotInferenceJob`; returns 201 immediately)
- [ ] 3.6 Create `Custom::Pilot::CopilotService` (loads thread, builds prompt with optional bound-conversation context + Logbook, runs RubyLLM chat asynchronously)
- [ ] 3.7 Create `Pilot::CopilotInferenceJob` (calls CopilotService; persists final assistant message; live streaming is optional/deferred)
- [ ] 3.8 Add polling/fetch support for completed Copilot messages; add ActionCable only if implementing optional streaming
- [ ] 3.9 Add Pundit policy `Pilot::CopilotThreadPolicy` (agent owns thread)
- [ ] 3.10 Create Vuex module `app/javascript/dashboard/store/pilot/copilot/` (threads list, active thread, messages, pending response state)
- [ ] 3.11 Create `CopilotDrawer.vue` under `components-next/pilot/copilot/` (sidebar icon trigger; drawer panel; message list; input; new-thread action)
- [ ] 3.12 Create `CopilotThreadList.vue` and `CopilotMessageList.vue` subcomponents (pending-state rendering; auto-scroll)
- [ ] 3.13 Wire Copilot sidebar icon into dashboard nav; gate on `pilot_copilot_enabled`; lazy-import
- [ ] 3.14 Add "Open Copilot bound to this conversation" affordance from inside customer conversation view
- [ ] 3.15 Add i18n strings to `en.json` for all Copilot UI labels
- [ ] 3.16 Write rspec for threads + messages controllers (CRUD, scoping, 404 on cross-agent)
- [ ] 3.17 Write rspec for `Pilot::CopilotInferenceJob` (mocked RubyLLM; verifies assistant message persistence)
- [ ] 3.18 Run `bundle exec rails assets:precompile` and verify

## 4. Autopilot — assistants, documents, scenarios, agent bot

- [ ] 4.1 Rebuild `Captain::Assistant` model (account-scoped; name; description; config store accessors; response_guidelines; guardrails; inboxes via `captain_inboxes`; scenarios; custom tool metadata)
- [ ] 4.2 Rebuild `Captain::Document` model (assistant-scoped source record; `external_link`, optional PDF, content, metadata, status/sync_status; enqueues crawl/response generation)
- [ ] 4.3 Rebuild `Captain::AssistantResponse` model as the searchable knowledge base (question/answer/status, polymorphic documentable, vector(1536), embedding refresh job)
- [ ] 4.4 Rebuild `Captain::Scenario` model (assistant-scoped; title/description/instruction/enabled/tools; validates and resolves tool references)
- [ ] 4.5 Add `Pilot::UpdateEmbeddingJob` for assistant responses and wire embedding refresh after response create/update
- [ ] 4.6 Rebuild `Captain::Inbox` join model (assistant ↔ inbox)
- [ ] 4.7 Add routes under `pilot/assistants` (CRUD + `:id/playground` + `tools`), nested `inboxes` (index/create/destroy), nested `scenarios` (CRUD), plus account-level `documents`, `assistant_responses`, and `bulk_actions`
- [ ] 4.8 Create `Api::V2::Accounts::Pilot::AssistantsController` (admin-only Pundit; CRUD + playground action)
- [ ] 4.9 Create `Api::V2::Accounts::Pilot::DocumentsController` (index/show/create/destroy; creates source documents; crawl/response generation jobs handle embeddings)
- [ ] 4.10 Create `Api::V2::Accounts::Pilot::ScenariosController`, `AssistantResponsesController`, `InboxesController`, and `BulkActionsController`
- [ ] 4.11 Create `Custom::Pilot::AutopilotService` / assistant chat service (uses message history, documentation-search over approved assistant responses, custom tools, and handover sentinel handling)
- [ ] 4.12 Create `Custom::Pilot::DocumentIngestionService` (fetches/crawls external links or PDFs into document content)
- [ ] 4.13 Create `Pilot::DocumentResponseBuilderJob` and `Pilot::UpdateEmbeddingJob` (generate FAQ-style assistant responses from documents and embed response question/answer text; use `low` queue)
- [ ] 4.14 Create `Custom::Pilot::HandoverEvaluator` (handles handover sentinel, customer human-request phrases, and scenario/handoff tool outcomes)
- [ ] 4.15 Create `Pilot::AutopilotInferenceJob` (triggered by `MessageCreatedEvent` on incoming customer messages in autopilot-attached inboxes; routes to AutopilotService or handover)
- [ ] 4.16 Hook into Chatwoot's message-created listener pattern to enqueue `Pilot::AutopilotInferenceJob`; gate on inbox-assistant link + `pilot_autopilot_enabled`
- [ ] 4.17 Implement handover behavior: skip auto-reply, set conversation status to `pending`, post a system note with reason
- [ ] 4.18 Implement scenario instruction/tool-reference resolution (markdown link `[Label](tool://<id>)` → extracted into `tools` JSONB) and validation; reject unknown tool ids; reject scenarios whose handoff tool name would exceed 60 characters
- [ ] 4.19 Implement `playground` controller action (accepts `message_content` and `message_history`; in-memory inference; persists nothing)
- [ ] 4.20 Add Pundit policies for all Autopilot resources (admin-only mutate; agent read-only)
- [ ] 4.21 Create Vuex module `app/javascript/dashboard/store/pilot/autopilot/` (assistants, documents, scenarios)
- [ ] 4.22 Create API client `app/javascript/dashboard/api/pilot/autopilot.js`
- [ ] 4.23 Create `AutopilotIndex.vue` (assistants list)
- [ ] 4.24 Create `AssistantEditor.vue` (name, description, config fields, response guidelines, guardrails, inbox picker, enabled toggle)
- [ ] 4.25 Create `DocumentList.vue` + `DocumentUploader.vue` (URL source, PDF upload, status/sync display)
- [ ] 4.26 Create `ScenarioBuilder.vue` (title, description, instruction editor with tool references, enabled toggle)
- [ ] 4.27 Create `PlaygroundPanel.vue` (message content + history input; render reply)
- [ ] 4.28 Add Pilot → Autopilot link in settings nav; gate on `pilot_autopilot_enabled`
- [ ] 4.29 Add i18n strings to `en.json` for all Autopilot UI
- [ ] 4.30 Write rspec for `AutopilotService` (vector search; handover triggers)
- [ ] 4.31 Write rspec for `DocumentIngestionService`, `DocumentResponseBuilderJob`, and `UpdateEmbeddingJob` (URL/PDF ingestion; FAQ response generation; dim assertion)
- [ ] 4.32 Write rspec for `HandoverEvaluator` (each of the three conditions)
- [ ] 4.33 Write rspec for Autopilot controllers (assistants, documents, scenarios, assistant responses, inboxes, bulk actions)
- [ ] 4.34 Run `bundle exec rails assets:precompile` and verify

## 5. Logbook — extraction job + viewer UI

- [ ] 5.1 Create migration for `pilot_logbook_entries` table (contact_id FK, account_id FK, content text, source_message_id FK nullable with `ON DELETE SET NULL`, extracted_at timestamp, timestamps)
- [ ] 5.2 Add index `(contact_id, created_at DESC)` and `(account_id)`
- [ ] 5.3 Create `Pilot::LogbookEntry` model (belongs_to contact, account, optional source_message; account-scoped default scope)
- [ ] 5.4 Create `Custom::Pilot::LogbookExtractionService` (takes a conversation; calls LLM with extraction prompt; returns array of fact strings). Behavioral reference for prompt shape: Captain's `Captain::Llm::ContactNotesService`. Do NOT call it directly; persist into `pilot_logbook_entries` only.
- [ ] 5.5 Create `Custom::Pilot::LogbookDeduplicator` (cosine-similarity dedupe at threshold `Pilot::Logbook::DEDUP_SIMILARITY_THRESHOLD = 0.92`; FIFO eviction at 100-entry soft cap)
- [ ] 5.6 Create `Pilot::LogbookExtractionJob` (runs extraction + dedupe + insert; uses `low` Sidekiq queue; idempotent by transcript hash)
- [ ] 5.7 Hook into `Conversation` after-update callback: enqueue extraction job when status transitions to `resolved` AND `pilot_logbook_enabled`
- [ ] 5.8 Extend `Custom::Pilot::BaseService` with `logbook_context_for(contact)` helper (returns formatted system-message string; returns empty when feature disabled or no entries)
- [ ] 5.9 Wire Logbook context into `BriefingService`, `CopilotService`, `AutopilotService` prompts
- [ ] 5.10 Add route `DELETE /api/v2/accounts/:account_id/pilot/logbook_entries/:id`
- [ ] 5.11 Create `Api::V2::Accounts::Pilot::LogbookEntriesController#destroy` (agent must have access to contact)
- [ ] 5.12 Add Pundit policy `Pilot::LogbookEntryPolicy`
- [ ] 5.13 Create `LogbookTab.vue` under `components-next/pilot/logbook/` (list entries; delete with confirmation; source-message link)
- [ ] 5.14 Mount Logbook tab into contact detail panel; gate on `pilot_logbook_enabled`
- [ ] 5.15 Add i18n strings to `en.json` for Logbook UI
- [ ] 5.16 Write rspec for `LogbookExtractionService` (mocked LLM; parsing)
- [ ] 5.17 Write rspec for `LogbookDeduplicator` (similarity threshold; FIFO eviction)
- [ ] 5.18 Write rspec for `LogbookExtractionJob` (enqueue on resolve; idempotency; skip when feature disabled)
- [ ] 5.19 Write rspec for `LogbookEntriesController#destroy`
- [ ] 5.20 Run `bundle exec rails assets:precompile` and verify

## 6. Tools — pluggable framework for Autopilot

- [ ] 6.1 Rebuild `Captain::CustomTool` model (account-scoped; generated slug; title; description; endpoint_url; request_template; response_template; auth_type/auth_config; param_schema; enabled flag; max 15 per account)
- [ ] 6.2 Add/port parameter schema validation for `param_schema`
- [ ] 6.3 Add optional hostname allowlist support if needed for Pilot SSRF policy; keep existing account-scoped tool storage compatible
- [ ] 6.4 Create `Custom::Pilot::ToolGuard` (resolves DNS; rejects RFC1918 / link-local / loopback / 169.254.169.254; rejects non-allowlisted hostnames)
- [ ] 6.5 Create `Custom::Pilot::ToolExecutor` (validates args against `param_schema`; performs HTTP with timeout; truncates body to 8 KB; returns result or error code)
- [ ] 6.6 Execute tools synchronously within the Autopilot inference loop (mirrors Captain's `CustomHttpTool`); no separate Sidekiq job — `ToolExecutor` is called in-process
- [ ] 6.7 Extend `Custom::Pilot::AutopilotService` to register enabled account custom tools alongside documentation search; suspend/resume the LLM loop on tool calls in-process
- [ ] 6.7a Implement structured error format (`{error, message}` with codes: `tool.timeout`, `tool.host_not_allowed`, `tool.private_ip_denied`, `tool.http_error`, `tool.parse_error`, `tool.disabled`) returned to the LLM as the tool result on any failure
- [ ] 6.7b Add instrumentation span `pilot.tool.custom_http` (input params redacted; tool_slug; assistant_id; duration_ms; http_status; error_code on failure)
- [ ] 6.8 Add account-level `pilot/custom_tools` routes (CRUD + collection/member `test` as appropriate)
- [ ] 6.9 Create `Api::V2::Accounts::Pilot::CustomToolsController` (CRUD + test action that runs ToolExecutor once with sample args)
- [ ] 6.10 Add Pundit policy `Pilot::CustomToolPolicy`
- [ ] 6.11 Create Vuex module `app/javascript/dashboard/store/pilot/tools/`
- [ ] 6.12 Create `ToolsPanel.vue` under `components-next/pilot/tools/` (CRUD list)
- [ ] 6.13 Create `ToolEditor.vue` (param schema editor, endpoint/method, request/response templates, auth config, enable toggle, "Test" button)
- [ ] 6.14 Mount Tools panel in Pilot settings or AssistantEditor.vue; gate on `pilot_tools_enabled`
- [ ] 6.15 Add i18n strings to `en.json` for Tools UI
- [ ] 6.16 Write rspec for `ToolGuard` (private IP rejection; allowlist enforcement; DNS rebinding case)
- [ ] 6.17 Write rspec for `ToolExecutor` (param schema validation; timeout; 8 KB truncation)
- [ ] 6.18 Write rspec for in-process tool execution path with WebMock (`ToolExecutor` + AutopilotService loop): tool selected → executed → result fed back to next LLM turn → final reply
- [ ] 6.19 Write rspec for `CustomToolsController` (CRUD + test action)
- [ ] 6.20 Run `bundle exec rails assets:precompile` and verify

## 7. Telemetry — event dispatch + webhooks + activity log

- [ ] 7.1 Create migration for `pilot_events` table (id, account_id FK, event_name, payload JSONB, related_entity_type/id, created_at) with index on `(account_id, created_at DESC)` and `(event_name)`
- [ ] 7.2 Create `Pilot::Event` model (account-scoped) with named scopes for prefix filtering
- [ ] 7.3 Create `Custom::Pilot::EventDispatcher` (single entry point; calls `Rails.configuration.dispatcher.dispatch(name, time, payload)` AND persists to `pilot_events`; applies sensitive-payload redaction rules)
- [ ] 7.4 Wire `EventDispatcher.dispatch(name, payload)` calls into every Pilot service at the documented points (Briefing start/complete/fail, Copilot inference, Autopilot inference + handover + document.crawled/responses_generated, Logbook extraction + entry.created/deleted, Tool invoked/completed/failed)
- [ ] 7.5 Register all `pilot.*` event names with Chatwoot's webhook event registry so they appear in the webhook subscription UI
- [ ] 7.6 Create per-account ActionCable channel `PilotEventsChannel` (subscribes by account; broadcasts events with the same payload shape as webhooks)
- [ ] 7.7 Add controller `Api::V2::Accounts::Pilot::EventsController#index` (paginated event log, filters by event_name prefix and date range; admin-only)
- [ ] 7.8 Create `Pilot::EventsRetentionJob` (daily; purges `pilot_events` rows older than 30 days)
- [ ] 7.9 Schedule `EventsRetentionJob` via sidekiq-cron / equivalent
- [ ] 7.10 Implement payload-redaction helper (`Custom::Pilot::PayloadRedactor`) — replaces raw prompts/tool-auth-headers/customer-message-bodies with length + sha256 fingerprint
- [ ] 7.11 Create Vue page `PilotActivity.vue` under `components-next/pilot/telemetry/` (event log table, filters, live tail via `PilotEventsChannel`)
- [ ] 7.12 Wire activity view into Pilot settings nav; gate on `pilot_enabled`
- [ ] 7.13 Add i18n strings for event names + activity view
- [ ] 7.14 Write rspec for `EventDispatcher` (dispatches AND persists; redacts; respects per-account scoping)
- [ ] 7.15 Write rspec for `EventsController#index` (pagination, filtering, admin-only)
- [ ] 7.16 Write rspec for `PayloadRedactor` (every sensitive field listed in pilot-telemetry spec is redacted)
- [ ] 7.17 Write rspec for `EventsRetentionJob` (purges old rows; respects retention window)
- [ ] 7.18 Run `bundle exec rails assets:precompile` and verify

## 8. Onboarding — wizard + connection test

- [ ] 8.1 Create migration adding `pilot_onboarding_state` JSONB column on `accounts` (default `{}`)
- [ ] 8.2 Create `Custom::Pilot::OnboardingState` value object with helpers for each step flag + `completed?`
- [ ] 8.3 Create `Custom::Pilot::ProviderConnectionTester` (issues a small `RubyLLM.chat` "ping" call with the supplied config; returns success or error class+message)
- [ ] 8.4 Create routes for `pilot/onboarding`: `GET` (state), `PATCH provider` (write config + test), `PATCH assistant`, `PATCH inbox`, `PATCH document`, `PATCH playground_tested`
- [ ] 8.5 Create `Api::V2::Accounts::Pilot::OnboardingController` (admin-only Pundit; each PATCH validates step input and updates the relevant JSONB key)
- [ ] 8.6 Add per-user dismissal preference (user `ui_settings.pilot_onboarding_dismissed` boolean)
- [ ] 8.7 Create Vuex module `app/javascript/dashboard/store/pilot/onboarding/`
- [ ] 8.8 Create `OnboardingWizard.vue` umbrella component (step navigator, progress bar)
- [ ] 8.9 Create step components: `Step1Provider.vue` (preset picker + custom form + Test Connection button), `Step2Assistant.vue`, `Step3Inbox.vue` (with "no inbox? create one" deflection), `Step4Document.vue` (PDF upload OR URL OR scenario), `Step5Playground.vue` (embedded playground)
- [ ] 8.10 Auto-surface wizard on dashboard mount when `pilot_enabled` AND `!completed_at` AND `!user_dismissed`
- [ ] 8.11 Add "Pilot Setup Wizard" link in Pilot settings (re-entry from anywhere)
- [ ] 8.12 Detect env-configured provider on wizard open; auto-run connection test against env values
- [ ] 8.13 Add i18n strings for all wizard steps
- [ ] 8.14 Write rspec for `OnboardingController` (each PATCH endpoint; admin-only)
- [ ] 8.15 Write rspec for `ProviderConnectionTester` (success + auth-error paths with mocked RubyLLM)
- [ ] 8.16 Write rspec for `OnboardingState` (`completed?` only when all 5 flags true)
- [ ] 8.17 Run `bundle exec rails assets:precompile` and verify

## 9. Auto-resolve — eligibility, scheduler, admin endpoint

- [ ] 9.1 Create migration adding `pilot_autoresolve_enabled` boolean (default `false`) and `pilot_autoresolve_config` JSONB (default `{}`) on `accounts`; partial index `accounts(id) WHERE pilot_autoresolve_enabled`
- [ ] 9.2 Create `Custom::Pilot::AutoResolveEligibility` predicate object encoding the six rules from pilot-autoresolve spec
- [ ] 9.3 Create `Custom::Pilot::AutoResolveService` (executes the resolve action for a single conversation: post resolution message, set status to resolved, dispatch event, create system note)
- [ ] 9.4 Create `Pilot::AutoResolveJob` (hourly scan; iterates accounts; runs eligibility query; enqueues per-conversation jobs)
- [ ] 9.5 Create `Pilot::AutoResolveConversationJob` (re-checks eligibility before resolving; runs `AutoResolveService`; idempotent)
- [ ] 9.6 Schedule `AutoResolveJob` via sidekiq-cron (`cron: '0 * * * *'`)
- [ ] 9.7 Implement business-hours-aware idle calculation in eligibility predicate (opt-in via `respect_business_hours`)
- [ ] 9.8 Add `POST /api/v2/accounts/:account_id/pilot/autoresolve/run_now` (admin-only synchronous trigger; returns `{ scanned, enqueued }`)
- [ ] 9.9 Add `GET/PATCH /api/v2/accounts/:account_id/pilot/autoresolve` for config management
- [ ] 9.10 Create `Api::V2::Accounts::Pilot::AutoresolveController` (admin Pundit; CRUD on config + run_now)
- [ ] 9.11 Create `AutoresolveSettings.vue` under `components-next/pilot/autoresolve/` (toggle, idle_hours input, resolution_message editor with preview, business-hours toggle, "Run now" button)
- [ ] 9.12 Mount Auto-resolve settings into Pilot settings nav; gate on `pilot_enabled`
- [ ] 9.13 Add i18n strings + default `pilot.autoresolve.default_message`
- [ ] 9.14 Write rspec for `AutoResolveEligibility` — one test per rule (open status, assistant interacted, idle window, no human after assistant, no prior auto-resolve attempt, business-hours mode)
- [ ] 9.15 Write rspec for `AutoResolveService` (resolves, posts message, dispatches event)
- [ ] 9.16 Write rspec for `AutoResolveConversationJob` (re-check passes → resolves; re-check fails → no-op)
- [ ] 9.17 Write rspec for `AutoresolveController` (CRUD; run_now)
- [ ] 9.18 Run `bundle exec rails assets:precompile` and verify

## 10. Utilities — Summary, CSAT, Follow-up, Rewrite, Label suggestion

- [ ] 10.1 Add migration: 5 boolean columns on `accounts` (`pilot_summary_enabled`, `pilot_csat_analysis_enabled`, `pilot_follow_up_enabled`, `pilot_rewrite_enabled`, `pilot_label_suggestion_enabled`; default `false`)
- [ ] 10.2 Create `Custom::Pilot::SummaryService` (wraps `Captain::SummaryService`; feature-flag gate; Logbook context injection; dispatches `pilot.summary.completed` event)
- [ ] 10.3 Create `Custom::Pilot::FollowUpService` (wraps `Captain::FollowUpService`; returns array of 1-3 suggestions)
- [ ] 10.4 Create `Custom::Pilot::RewriteService` (wraps `Captain::RewriteService`; validates tone is in the allowed enum; returns rewritten text)
- [ ] 10.5 Create `Custom::Pilot::CsatAnalysisService` (wraps `Captain::CsatUtilityAnalysisService`; returns `{ sentiment, themes, escalation_recommended }`)
- [ ] 10.6 Create `Custom::Pilot::LabelSuggestionService` (wraps `Captain::LabelSuggestionService`; returns array of existing label ids for the account)
- [ ] 10.7 Add migration: `suggested_label_ids` integer[] column on `conversations` (default `{}`)
- [ ] 10.8 Add migration: CSAT analysis columns on `csat_survey_responses` (`pilot_sentiment` string, `pilot_themes` text[], `pilot_escalation_recommended` boolean)
- [ ] 10.9 Create `Pilot::CsatAnalysisJob` (enqueued after CSAT response with comment; persists analysis fields)
- [ ] 10.10 Hook `Pilot::CsatAnalysisJob` enqueue into `CsatSurveyResponse` after_create callback when comment present AND feature enabled
- [ ] 10.11 Create `Pilot::LabelSuggestionJob` (enqueued after conversation create or first customer message; persists `suggested_label_ids`)
- [ ] 10.12 Hook `Pilot::LabelSuggestionJob` enqueue into conversation-created listener when feature enabled
- [ ] 10.13 Add routes: `POST pilot/summaries`, `POST pilot/follow_ups`, `POST pilot/rewrites`
- [ ] 10.14 Create `Api::V2::Accounts::Pilot::SummariesController#create`, `FollowUpsController#create`, `RewritesController#create` (each: agent auth, feature flag gate, conversation access where applicable)
- [ ] 10.15 Add Pundit policies for each utility endpoint
- [ ] 10.16 Create Vue affordances:
  - [ ] 10.16a `SummarizeButton.vue` in conversation header (popover with result)
  - [ ] 10.16b `FollowUpSuggestionsButton.vue` in composer (chips that insert text)
  - [ ] 10.16c `RewriteToolbar.vue` floating toolbar on composer text selection (tone picker → replace selection)
  - [ ] 10.16d `SuggestedLabelChips.vue` above the conversation label selector
  - [ ] 10.16e CSAT report enhancements: sentiment/themes aggregation view (no new top-level component — extends existing CSAT report page)
- [ ] 10.17 Gate each UI affordance on its per-feature flag; lazy-import
- [ ] 10.18 Add i18n strings for all utility UI labels
- [ ] 10.19 Write rspec for each `Custom::Pilot::*Service` (delegates correctly; feature gate; telemetry event)
- [ ] 10.20 Write rspec for each utility controller
- [ ] 10.21 Write rspec for `CsatAnalysisJob` and `LabelSuggestionJob` (enqueue on the right event; persist results; respect feature flag)
- [ ] 10.22 Run `bundle exec rails assets:precompile` and verify

## 11. Cleanup and release prep

- [ ] 11.1 Delete the three stub composables (`useCaptain.js`, `useCopilotReply.js`, `useLabelSuggestions.js`); update any imports to use Pilot composables
- [ ] 11.2 Add Super Admin "Pilot Setup" page or notes (links to `PILOT_PRESETS.md`; shows current resolved config values from `GlobalConfigService`)
- [ ] 11.3 Update `_KONVERSIO/HANDOFF.md`: mark Phase 2 done; document the live env-var contract; document new operational gotchas observed during rollout
- [ ] 11.4 Add a CHANGELOG entry for the Pilot release
- [ ] 11.5 Manual smoke test against `konversio.migrately.nl` with Scaleway/Mistral preset: Briefing button generates a draft; Copilot drawer answers; Autopilot replies to a test inbox; Logbook captures a fact after resolution; a sample Tool fires from Autopilot; Onboarding wizard completes for a fresh test account; Auto-resolve fires on a test idle conversation; Summary/Follow-up/Rewrite/Label-suggestion all visible and functional; Pilot Activity view shows the events from the test run
- [ ] 11.6 Run `bundle exec rubocop -a`
- [ ] 11.7 Run `pnpm eslint:fix`
- [ ] 11.8 Run full `bundle exec rspec` suite
- [ ] 11.9 Final `bundle exec rails assets:precompile` before `git push heroku main`
- [ ] 11.10 Tag release `v0.3.0-pilot` after deploy verified in production
