## Tasks

### Backend

1. - [x] **Migration** — add nullable `ai_assignee_type` string column to `conversations` plus a composite index on `(assignee_agent_bot_id, ai_assignee_type)`; no backfill.
2. - [x] **Assistant config accessors** — in `app/models/pilot/assistant.rb` extend the `store_accessor :config` list with `:audience` (read-only raw hash), `:response_window`, `:auto_resolve_mode`, `:auto_resolve_after`, `:send_inactivity_resolution_message`; add per-assistant `auto_resolve_mode` reader falling back to `Account#pilot_auto_resolve_mode` (default `evaluated`), stamped at create; `inactivity_threshold_minutes` reader (`auto_resolve_after` → `PILOT_AUTORESOLVE_IDLE_MINUTES` global → 60).
3. - [x] **Assistant validations** — validate `response_window` inclusion (`always` / business-hours / outside-business-hours identifiers, blank allowed); `auto_resolve_mode` inclusion; `auto_resolve_after` integer within 5..1440, normalized to 5-minute steps before validation; `send_inactivity_resolution_message` boolean.
4. - [x] **Audience validator** — new service (e.g. `app/services/pilot/audience/tree_validator.rb`) registered as a model validator on `Pilot::Assistant`: enforces group/leaf shape, non-empty condition arrays, max depth 3, per-attribute allowed operators (standard attributes + custom-attribute display types from `CustomAttributeDefinition`), and value requirements per operator; adds a `config` error on failure.
5. - [x] **Audience matcher** — new service (e.g. `app/services/pilot/audience/matcher.rb`): in-memory evaluation of the tree against a contact + conversation; attribute resolution over contact standard/additional attributes, contact labels, conversation additional attributes, HMAC verification state, and contact custom attributes; semantics aligned with core filtering (case-insensitive text, `+`-insensitive phone, label has-tag, checkbox unset = false, numeric compare for number/currency/percent custom attributes, ISO date strings as dates, blank/unparseable never matches range operators); blank tree matches everything.
6. - [x] **Engagement predicate** — `Pilot::Assistant#engages?(contact, conversation)` = audience match AND response-window availability (`always` or blank → true; otherwise use `Inbox#working_hours_enabled?` / `OutOfOffisable#out_of_office?`; inboxes without working hours configured are always available).
7. - [x] **Conversation AI assignee** — in `app/models/conversation.rb`: polymorphic `ai_assignee` reader (`AgentBot` or `Pilot::Assistant` via `assignee_agent_bot_id` + `ai_assignee_type`, NULL type = legacy `AgentBot`); `bot_handoff!` clears it; human assignment clears it; update `unassigned` / `assigned` scopes and the assignee display fallback to include the AI assignee.
8. - [x] **Status determination gate** — in `Conversation#determine_conversation_status`: when the inbox has a Pilot assistant and no external bot is active, a non-engaging conversation starts `open` instead of `pending`; an engaging assistant is set as `ai_assignee` when no human assignee is present.
9. - [x] **Resolution message service** — new service (e.g. `app/services/pilot/conversations/resolution_message_service.rb`): no-op when the assistant toggle is off; posts assistant-configured message else localized default (`I18n.with_locale(account.locale)`) as an outgoing assistant-authored message; used by both time-based and evaluated resolution paths.
10. - [x] **AutoResolveService per-assistant lifecycle** — update `custom/app/services/custom/pilot/auto_resolve_service.rb` to read mode/threshold/message-toggle from the assistant (with the existing account/global fallbacks), delegate message posting to the new resolution-message service, and support silent resolution (no customer message, activity still recorded) when the toggle is off.
11. - [x] **Sweep locking** — in `app/jobs/pilot/conversations/resolution_job.rb`: per-assistant cutoff from `inactivity_threshold_minutes`; skip when assistant blank or mode `disabled`; wrap each transition in `conversation.with_lock` with a re-check (still `pending`, still idle) inside the lock; keep the existing post-evaluation `still_eligible?` re-check; rescue `ActiveRecord::RecordNotFound` per conversation.
12. - [x] **Assistant API** — in `app/controllers/api/v1/accounts/pilot/assistants_controller.rb`: permit the new config keys (audience passed through as raw hash, validated by the model validator); merge partial `config` updates with existing config inside a lock so concurrent edits don't clobber keys; surface validation errors as 422.
13. - [x] **Scenario API** — in `app/controllers/api/v1/accounts/pilot/scenarios_controller.rb`: index returns all scenarios (not only `enabled`); ensure `enabled` is updatable and exposed in the payload.
14. - [x] **Custom tool API** — expose per-tool count of enabled scenarios referencing the tool (jsonb containment on `pilot_scenarios.tools` by slug) in the tool payload; ensure `enabled` is updatable; disabled tools excluded from every assistant's live toolset and from `Pilot::Scenario` known-tool validation.
15. - [x] **Assignment service + assignable agents** — in `app/services/conversations/assignment_service.rb`: assigning an AI assignee (agent bot or Pilot assistant) clears human assignee and sets `pending`; assigning a human to an AI-held conversation clears the AI assignee, opens the conversation, and stamps `waiting_since`; both inside `with_lock`. In `app/controllers/api/v1/accounts/assignable_agents_controller.rb` + jbuilder: opt-in `include_ai_assignees` param appends account Pilot assistants (with an assignee-type discriminator) to the payload.
16. - [x] **I18n** — add backend strings (validation messages, default resolution copy if missing) to `en.yml` only.

### Frontend

17. - [ ] **Audience settings page** — in the Pilot assistant settings area (`app/javascript/dashboard/routes/dashboard/pilot/AssistantEditor.vue` or a dedicated settings route): everyone/specific-audience mode selector; condition-tree builder (AND/OR root group, one nested sub-group level, leaf rows with attribute + operator + value inputs) reusing the advanced-filter attribute/operator primitives; empty-audience validation; save via assistant update API.
18. - [ ] **Schedule settings section** — radio-card selector for the three response-window options with explanatory hint text; save via assistant update API.
19. - [ ] **Inactivity settings section** — auto-resolve mode radio cards (time-based / evaluated / disabled, showing the inherited account default), duration picker (5-minute steps, 5 min–24 h) hidden when disabled, resolution-message textarea and "send resolution message" toggle wired to the new config keys.
20. - [ ] **Scenario list toggle** — in the assistant's scenario list: per-row enable/disable switch with pending state and success/error alerts.
21. - [ ] **Tools page toggle** — in `app/javascript/dashboard/routes/dashboard/pilot/tools/`: per-tool enable/disable switch; disabling a tool referenced by enabled scenarios opens a confirmation dialog stating the referencing-scenario count.
22. - [ ] **Assignee UI** — request `include_ai_assignees` where the dashboard shows the assignee selector; render AI assignee entries with a bot icon and type discriminator; handle AI assignee display on conversation cards/details.
23. - [ ] **I18n** — add all new frontend strings to `en.json` only; no bare strings in templates.

### Validation

24. - [x] **Model specs** — assistant validation (mode/window/threshold bounds and stepping, audience validator accept/reject matrix), matcher semantics (each operator, nested AND/OR, depth limit, blank tree), engagement predicate across window × working-hours combinations.
25. - [x] **Job/service specs** — `Pilot::Conversations::ResolutionJob` + `Custom::Pilot::AutoResolveService`: per-assistant mode routing, per-assistant cutoff, locked transition skips raced conversations, toggle-off resolution posts no customer message, evaluated path resolve/handoff, RecordNotFound resilience.
26. - [x] **Assignment specs** — `Conversations::AssignmentService` AI/human transitions (status, waiting_since, clearing), `bot_handoff!` clearing, scope changes, assignable-agents opt-in payload.
27. - [x] **API request specs** — assistant config permit + audience 422s, partial config merge, scenario index including disabled, tool referenced-count, tool exclusion when disabled.
28. - [ ] **Manual smoke test** — assistant with audience + business-hours window on a web widget inbox: matching contact inside hours → pending with AI assignee and AI replies; non-matching contact → open, no AI; outside hours → open; idle past threshold → resolved with (or without, per toggle) resolution message; disable a referenced tool → confirmation dialog shows count.

## Dependencies / Order

- 1 → 7 → 8 → 15 (schema before assignment logic before UI-facing assignment API).
- 2 → 3 → 6 (accessors before validations before predicate); 4 and 5 depend on 2; 6 depends on 4 + 5.
- 8 depends on 6.
- 9 → 10 → 11 (message service before sweep rewiring).
- 12 depends on 3 + 4; 17–19 depend on 12.
- 13, 14 are independent of each other; 20 depends on 13, 21 depends on 14.
- 22 depends on 15.
- 24–27 run alongside their implementation tasks; 28 is last.
