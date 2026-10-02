# Implementation Report: pilot-audiences-and-lifecycle

Date: 2026-10-02. Branch: `feat/pilot-audiences-and-lifecycle` (worktree `tmp/wt-audiences`).
All work implemented clean-room from the change specs + existing `Pilot::` code. No upstream `enterprise/` sources were read.

## What was implemented (per spec section)

### pilot-audience-targeting
- `pilot_assistants.config['audience']` stores a recursive condition tree (group = combinator + non-empty `conditions`; leaf = `attribute_key` + `filter_operator` + `values`), persisted via the assistant API (`config: {}` strong params pass the raw hash through) and returned verbatim on reads.
- `Pilot::Audience::TreeValidator` (`app/services/pilot/audience/tree_validator.rb`), registered as a model validator on `Pilot::Assistant`: enforces group/leaf shape, AND/OR combinators, non-empty condition lists, max depth 3 (root group → one sub-group level → leaves), per-attribute operator allowlists (standard attributes + custom-attribute display types from the account's `CustomAttributeDefinition`s), values required for value operators and forbidden for `is_present`/`is_not_present`. Failure adds a `:config` error → API responds 422.
- `Pilot::Audience::Matcher` + `Pilot::Audience::ValueResolver` (`app/services/pilot/audience/`): in-memory evaluation over contact standard attributes, contact additional attributes (country/city/company), contact labels (has-tag), conversation additional attributes (browser_language/referer/conversation_language), widget HMAC state (`identity_verified` via `contact_inbox.hmac_verified`), and contact custom attributes. Semantics mirror core filtering: case-insensitive text, `+`-insensitive phone, checkbox unset = false, numeric compare for number/currency/percent, ISO dates as dates, blank/unparseable never matches range operators, SQL-NULL-style negations. Blank tree matches everything.
- Creation-time gating in `Conversation#determine_conversation_status`: on a Pilot-only inbox a non-matching conversation starts `open` (no AI assignee); a matching one starts `pending` with the assistant as AI assignee. In-flight conversations are never re-gated. With an external bot (agent bot / dialogflow) also active, legacy behavior wins.

### pilot-response-schedule
- `config['response_window']` ∈ `always` / `business_hours` / `outside_business_hours` (blank = always), model-validated.
- `Pilot::Assistant#response_window_available?(inbox)` uses `Inbox#working_hours_enabled?` / `OutOfOffisable#out_of_office?`; inboxes without working hours are always available. Combined with the audience check in `Pilot::Assistant#engages?` (both must pass, else the conversation starts `open` with no AI assignee).

### pilot-inactivity-handling
- `PilotAssistantLifecycle` concern (`app/models/concerns/pilot_assistant_lifecycle.rb`, included in `Pilot::Assistant`): config accessors + validations for `auto_resolve_mode` (inclusion; reader falls back to `Account#pilot_auto_resolve_mode`; stamped with the account value at create), `auto_resolve_after` (integer 5..1440, normalized to 5-minute steps before validation; reader `inactivity_threshold_minutes` falls back to `PILOT_AUTORESOLVE_IDLE_MINUTES` then 60), and `send_inactivity_resolution_message` (boolean, default true).
- `Pilot::Conversations::ResolutionMessageService` (`app/services/pilot/conversations/resolution_message_service.rb`) — the single post-or-stay-silent decision point: no-op when the toggle is off; assistant's custom copy when set; else the localized default in the account locale (`I18n.with_locale`), posted as an outgoing assistant-authored message.
- `Custom::Pilot::AutoResolveService` reads mode/threshold from the assistant (account/global fallbacks kept), delegates message posting to the new service, and wraps both resolve and handoff transitions in `conversation.with_lock` with a pending+idle re-check inside the lock; the evaluated path keeps its post-LLM re-check. Silent resolution (toggle off) still records the private-note/system record via `ConversationResolver`.
- `Pilot::Conversations::ResolutionJob` builds an inbox→assistant map per account (skipping `disabled` assistants and email inboxes), prefilters with the smallest per-assistant threshold, keeps the per-run volume cap, and rescues `ActiveRecord::RecordNotFound` per conversation (deleted mid-sweep → skip silently).

### pilot-ai-assignment
- Migration `20261004000000_add_ai_assignee_type_to_conversations.rb`: nullable `conversations.ai_assignee_type` + composite concurrent index on `(assignee_agent_bot_id, ai_assignee_type)`. No backfill; NULL type + present id reads as legacy `AgentBot`.
- `Conversation#ai_assignee` polymorphic reader/writer over `assignee_agent_bot_id`; writer clears the human assignee; `reset_agent_bot_when_assignee_present` clears both AI columns; `unassigned`/`assigned` scopes treat the AI assignee as an assignee; `assigned_entity`/`assignee_type` include the assistant; `bot_handoff!` clears the AI assignee (and keeps the `waiting_since` stamp).
- Conversation payload (`api/v1/conversations/partials/_conversation.json.jbuilder`) emits a `Pilot::Assistant` assignee branch (id/name/avatar_url + `assignee_type`). Conversation cards already rendered AI assignees via `assignee_type`.
- `Conversations::AssignmentService`: all transitions under `with_lock`; AI assignment (agent bot or Pilot assistant) clears the human assignee and sets `pending`; human takeover of an AI-held conversation clears the AI assignee, opens the conversation, and stamps `waiting_since`. The assignments controller renders the assistant with an `assignee_type` discriminator.
- Assignable-agents API: opt-in `include_ai_assignees` param appends `ai_assignees` (Pilot assistants + agent bots with `assignee_type` discriminator) to the payload; default payload unchanged. Frontend: the selector fetches with the opt-in, shows AI entries with a bot icon, and posts `assignee_type` on selection.

### pilot-scenario-tool-controls
- Scenario index already returns all scenarios with `enabled`; `enabled` updatable; run time already registers only `scenarios.enabled` (verified, covered by specs).
- `Pilot::CustomTool#referencing_enabled_scenarios_count` (jsonb containment on `pilot_scenarios.tools` by slug) exposed as `referencing_scenarios_count` in the tool payload; `enabled` updatable via the API.
- Disabled tools are excluded from every assistant's live toolset (`enabled_custom_tools` scopes `.enabled`) and from scenario known-tool validation (already `.enabled`); stored references are preserved and re-enabling restores behavior (spec-covered).
- Frontend: per-row scenario toggle with pending state + alerts; tool disable shows a confirmation dialog stating the referencing-scenario count (no dialog when unreferenced).

### i18n
- Backend: default resolution copy already existed in `en.yml` (`conversations.pilot.resolution`); validation messages are model error strings (repo convention, cf. `Pilot::Scenario`).
- Frontend: all new strings added to `app/javascript/dashboard/i18n/locale/en/pilot.json` only (`PILOT.SETTINGS.AUDIENCE/SCHEDULE/INACTIVITY`, scenario toggle toasts, tool disable confirm).

## Files added/changed

Added (backend): `db/migrate/20261004000000_add_ai_assignee_type_to_conversations.rb`, `app/models/concerns/pilot_assistant_lifecycle.rb`, `app/services/pilot/audience/{tree_validator,matcher,value_resolver}.rb`, `app/services/pilot/conversations/resolution_message_service.rb`.
Changed (backend): `app/models/pilot/assistant.rb`, `app/models/pilot/custom_tool.rb`, `app/models/conversation.rb`, `custom/app/services/custom/pilot/auto_resolve_service.rb`, `app/jobs/pilot/conversations/resolution_job.rb`, `app/services/conversations/assignment_service.rb`, `app/controllers/api/v1/accounts/pilot/assistants_controller.rb` (partial config deep-merge inside `with_lock`), `app/controllers/api/v1/accounts/conversations/assignments_controller.rb`, `app/controllers/api/v1/accounts/assignable_agents_controller.rb`, `app/views/api/v1/accounts/assignable_agents/index.json.jbuilder`, `app/views/api/v1/conversations/partials/_conversation.json.jbuilder`, `app/views/api/v2/accounts/pilot/custom_tools/_custom_tool.json.jbuilder`, `db/schema.rb`.
Added (frontend): `components-next/pilot/assistant/{AudienceBuilder.vue,audienceProvider.js,audienceProvider.spec.js}`.
Changed (frontend): `routes/dashboard/pilot/AssistantEditor.vue`, `routes/dashboard/pilot/ScenarioBuilder.vue`, `components-next/pilot/tools/ToolCard.vue`, `api/assignableAgents.js`, `api/inbox/conversation.js`, `store/modules/inboxAssignableAgents.js`, `store/modules/conversations/actions.js`, `composables/useAgentsList.js`, `routes/dashboard/conversation/ConversationAction.vue`, `store/modules/specs/inboxAssignableMembers/actions.spec.js`, `i18n/locale/en/pilot.json`.

Specs added/extended: `spec/models/pilot_assistant_lifecycle_spec.rb`, `spec/models/conversation_ai_assignee_spec.rb`, `spec/models/pilot/scenario_tool_controls_spec.rb`, `spec/services/pilot/audience/{tree_validator,matcher}_spec.rb`, `spec/services/pilot/conversations/resolution_message_service_spec.rb`, `spec/services/custom/pilot/auto_resolve_service_spec.rb`, `spec/jobs/pilot/conversations/resolution_job_spec.rb`, `spec/controllers/api/v1/accounts/pilot/scenarios_controller_spec.rb`, plus extensions to assistants/custom-tools/assignable-agents/assignments controller specs and the assignment-service spec.

## Migrations
- `20261004000000_add_ai_assignee_type_to_conversations.rb` (unique version; additive nullable column + concurrent composite index). Ran `RAILS_ENV=test bundle exec rails db:migrate` against `chatwoot_test_audiences`; `db/schema.rb` committed.

## Test commands + results
- `RAILS_ENV=test bundle exec rspec` on all change-related specs (audience, lifecycle, sweep, assignment, API): **all green**. Full affected-area run: 631 examples, 2 failures — both pre-existing on main (`custom_tools_controller` `/test` endpoint; verified failing at `54ad9721e` via detached checkout, same for the 9 `spec/lib/pilot/tools/executor_spec.rb` failures in that family; they attempt real HTTP under WebMock).
- One transient burst of 10 `conversation_spec.rb` custom-sort failures appeared in a single heavily-loaded combined run; not reproducible in 15+ subsequent runs across seeds 0–12/100–106/777/424242 (only one wall-clock `be_within(1.second)` timing flake under load, which is machine-dependent).
- `bundle exec rubocop -a` on all touched Ruby files: no offenses.
- `pnpm eslint` on all touched JS/Vue files: 0 errors (repo-wide warnings pre-exist).
- `pnpm test` on related vitest specs (useAgentsList, inboxAssignableMembers, assignableAgents API, hotkeys, audienceProvider): 30/30 passed.
- Manual smoke (task 28) via `RAILS_ENV=test bundle exec rails runner` end-to-end: matching contact → `pending` + AI assignee; non-matching → `open`; business-hours window outside hours → `open`; idle sweep past per-assistant threshold → resolved with default message; toggle off → resolved silently (0 customer messages, activity note kept); referenced tool count = 1 and disabled tool excluded from toolset; `bot_handoff!` clears the AI assignee.

## Deviations from spec
- Task 11 said the sweep lock lives in `resolution_job.rb`; the locked transition is implemented in `Custom::Pilot::AutoResolveService` (the component that performs the transition), which the job calls per conversation — same semantics (re-check inside `with_lock` before every transition, plus the post-LLM re-check), single home for the policy.
- The frontend audience/schedule/inactivity controls live in the existing `AssistantEditor.vue` (task 17 explicitly allowed this); the resolution-message textarea stays in the Messages section while its toggle lives in the Inactivity section.
- The human-takeover `open` transition is gated on an AI assignee being present, per spec; assigning a human to a `pending` conversation without an AI assignee keeps legacy behavior.

## Blockers / deferrals
- Pre-existing, unrelated failures on main (not caused by this change, verified on `54ad9721e`): 2 examples in `spec/controllers/api/v2/accounts/pilot/custom_tools_controller_spec.rb` (`/test` endpoint) and 9 in `spec/lib/pilot/tools/executor_spec.rb` — WebMock unregistered-request errors.
- Task 28's browser-level smoke (audience builder UI round-trip, confirmation dialog) was verified at the API/store level and via vitest; no live dev-server click-through was done in the worktree.
