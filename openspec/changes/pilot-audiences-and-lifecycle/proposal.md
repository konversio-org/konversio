## Why

Pilot assistants today engage every conversation on their attached inboxes with no way to restrict *who* they respond to or *when*. Admins cannot target specific contacts (e.g. only verified widget users, only a given country, only non-VIP segments), and cannot confine the assistant to business hours — or deliberately to after-hours coverage.

The inactivity lifecycle is similarly blunt. The auto-resolve mode is account-wide (`Account#pilot_auto_resolve_mode`), the idle window is a deployment-global constant (`PILOT_AUTORESOLVE_IDLE_MINUTES`, default 60 minutes), and every auto-resolution posts a customer-facing message with no way to suppress it per assistant. An account running multiple assistants with different service levels cannot tune any of this per assistant.

Conversations handled by Pilot also have no first-class AI assignee: they sit `pending` with no owner, so operators cannot see that the AI is in charge, and the assignment APIs only understand humans and webhook agent bots. Finally, scenarios and custom tools can only be created or deleted — there is no way to temporarily disable a scenario, and no guard against disabling a custom tool that active scenarios still reference.

Upstream Chatwoot shipped equivalent controls in v4.17.0 (audiences, schedules, inactivity handling, knowledge usage) and v4.18.0 (AI assignment, scenario and tool controls) as **Enterprise-only** Captain features. This change re-expresses that functionality as original, requirements-level specifications for Konversio's MIT Pilot layer (see `design.md` for the clean-room approach). Knowledge-usage *analytics* (per-conversation knowledge record tracking, coverage stats) are intentionally out of scope here — they are covered by the `pilot-faq-suggestions` and `pilot-agent-sessions-and-citations` changes.

## What Changes

- **Audience targeting**: add a per-assistant audience condition tree stored in `pilot_assistants.config.audience`. A nested group/leaf tree (AND/OR groups of attribute conditions over contact, conversation, and custom attributes) decides whether the assistant engages a conversation. Server-side validation enforces tree shape, nesting depth, and per-attribute operator compatibility.
- **Response schedule**: add a per-assistant response window (`always` / business hours only / outside business hours only), evaluated against the inbox's existing working-hours configuration.
- **Per-assistant inactivity lifecycle**: move auto-resolve controls from account level to the assistant: per-assistant auto-resolve mode (disabled / time-based / evaluated, defaulting to the account setting), per-assistant inactivity threshold in minutes (bounded, stepped, default 60), and a toggle controlling whether an inactivity resolution message is posted to the customer.
- **Resolution message delivery**: a single service decides and posts the customer-facing auto-resolution message (custom assistant copy, localized default, or nothing when disabled), used by every auto-resolution path.
- **AI assignment**: conversations gain a polymorphic AI assignee (agent bot or `Pilot::Assistant`). An engaged assistant becomes the conversation's AI assignee when no human is assigned; handoff and human assignment clear it. The assignable-agents API can optionally include AI assignees.
- **Scenario and tool enablement controls**: the scenario list returns all scenarios (not only enabled ones) with a per-row enable/disable toggle; only enabled scenarios are active at run time. Custom tools can be enabled/disabled from the Tools page; disabling a tool shows a confirmation stating how many enabled scenarios still reference it; disabled tools are excluded from every assistant's toolset.

## Capabilities

### New Capabilities
- `pilot-audience-targeting`: Per-assistant audience condition trees that decide whether a Pilot assistant engages a conversation, with server-side validation and evaluation semantics aligned with core contact filtering.
- `pilot-response-schedule`: Per-assistant response windows gating Pilot engagement to always, business hours, or outside business hours, based on inbox working hours.
- `pilot-inactivity-handling`: Per-assistant auto-resolve mode, inactivity threshold, and resolution-message toggle driving the System B idle-conversation sweep, including locked, idempotent status transitions.
- `pilot-ai-assignment`: Polymorphic AI assignee on conversations, automatic assignment of the engaged assistant, clearing on handoff/human assignment, and opt-in AI entries in the assignable-agents API.
- `pilot-scenario-tool-controls`: Enable/disable toggles for scenarios and custom tools, with referenced-tool protection and run-time exclusion of disabled items.

### Modified Capabilities
None — no existing capability spec covers Pilot engagement gating or the System B sweep; the account-level auto-resolve mode is superseded (with fallback) rather than modified in place.

## Impact

- `pilot_assistants.config` — new keys: `audience`, `response_window`, `auto_resolve_mode`, `auto_resolve_after`, `send_inactivity_resolution_message` (no schema change; jsonb)
- `conversations` — new `ai_assignee_type` column + composite index (migration required)
- `app/models/pilot/assistant.rb` (config accessors, validations, engagement predicate), `app/models/conversation.rb` (polymorphic AI assignee, status determination, handoff), `app/models/pilot/scenario.rb` (known-tool validation), `app/models/pilot/custom_tool.rb` (referenced-scenario count)
- New audience matching/validation services under `app/services/pilot/`
- `custom/app/services/custom/pilot/auto_resolve_service.rb`, `app/jobs/pilot/conversations/resolution_job.rb` and `resolution_scheduler_job.rb` (per-assistant mode/threshold, locking)
- API: `app/controllers/api/v1/accounts/pilot/assistants_controller.rb`, `scenarios_controller.rb`, custom tools controller, `assignable_agents_controller.rb`, conversations assignments service
- Frontend: Pilot assistant settings pages (audience builder, schedule, inactivity controls), scenario list and Tools page toggles, conversation assignee selector
- Backend i18n → `en.yml`, frontend i18n → `en.json` only
