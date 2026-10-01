## Context

Konversio's Pilot layer has its own architecture that predates these controls:

- `Pilot::Assistant` (`pilot_assistants`, jsonb `config`) owns documents, responses, scenarios, and inbox attachments. Config already carries `welcome_message`, `handoff_message`, `resolution_message`, and feature toggles via `store_accessor`.
- **System B** (the auto-resolve sweep) is `Pilot::Conversations::ResolutionSchedulerJob` → `Pilot::Conversations::ResolutionJob` → `Custom::Pilot::AutoResolveService`. The mode is account-wide (`Account#pilot_auto_resolve_mode`, values `disabled` / `legacy` / `evaluated`), the idle window is the global `PILOT_AUTORESOLVE_IDLE_MINUTES` (default 60), and resolution always posts a customer-facing message (`Custom::Pilot::ConversationResolver.resolve!` with `post_message:`).
- `Conversation#determine_conversation_status` sets new bot conversations to `pending`; `bot_handoff!` transitions to `open` and clears `assignee_agent_bot_id`. The only non-human assignee concept is `assignee_agent_bot` (webhook `AgentBot`).
- Inbox working hours already exist in core (`working_hours_enabled?`, `OutOfOffisable#out_of_office?`).

Upstream Chatwoot implemented the equivalent feature set inside `enterprise/` (EE-licensed): an audience matcher/validator pair, assistant config additions (`response_window`, `auto_resolve_mode`, `auto_resolve_after`, `send_inactivity_resolution_message`), a resolution-message service, a polymorphic `ai_assignee` on conversations, and scenario/tool enable toggles.

**License position: every item in this change is EE → clean-room.** The upstream enterprise code was read for behavioral understanding only. These specs express functional requirements in original wording against Konversio's `Pilot::` architecture; no upstream prompt text, UI copy, class names, or EE file content is ported. The one deliberate overlap with upstream vocabulary is the condition-tree *data shape* (`attribute_key` / `filter_operator` / `values` / operator names like `equal_to`, `contains`), because that vocabulary originates in the **MIT core** contact-filter system (`Contacts::FilterService` and the advanced-filter UI) that Konversio already ships — reusing it keeps audiences consistent with contact segments and custom filters, and is legally unencumbered.

## Goals / Non-Goals

**Goals:**

- Per-assistant audience condition trees: storage, validation, evaluation, and engagement gating.
- Per-assistant response windows driven by inbox working hours.
- Per-assistant inactivity lifecycle: mode, threshold, resolution-message toggle; locked and idempotent sweep transitions.
- One service that decides/posts the auto-resolution customer message.
- Polymorphic AI assignee on conversations with automatic assignment of the engaged assistant and correct clearing semantics.
- Enable/disable controls for scenarios and custom tools with referenced-tool protection.

**Non-Goals:**

- Knowledge-usage analytics, outcome classification, and assistant stats (covered by `pilot-faq-suggestions`, `pilot-conversation-outcomes`, `pilot-agent-sessions-and-citations`).
- Playground/runtime configuration overrides for audiences or schedules.
- Renaming the existing `assignee_agent_bot_id` column.
- Changing the System B cadence (scheduler frequency stays as-is).
- Per-inbox (rather than per-assistant) audience or schedule configuration.
- Backfilling `ai_assignee` for historical conversations.

## Decisions

### Store all new assistant settings in `pilot_assistants.config` (jsonb)

Audience tree, response window, auto-resolve mode, inactivity threshold, and the resolution-message toggle are all per-assistant configuration and live in the existing `config` jsonb column, exposed through `store_accessor`. The audience tree is passed through strong params as a raw hash (it is recursive and cannot be whitelisted by shape) and validated by a dedicated validator.

Alternatives considered:
- Dedicated columns per setting. Cleaner types, but five migrations for settings that are inherently schemaless feature config; the audience tree does not fit a column anyway.
- A new `pilot_assistant_settings` table. Over-normalized; every consumer already reads `config`.

Rationale: matches the existing Pilot config pattern; one validator guards the only structurally complex key.

### Audience semantics mirror core contact filtering

Audience leaves use the same attribute keys and operator names as the core (MIT) contact/conversation filter system, and equality/comparison semantics behave the same way: text compares case-insensitively, phone numbers compare ignoring the `+` prefix, label conditions are has-tag checks, checkbox custom attributes treat unset as false, numeric custom attributes compare numerically, ISO date strings in custom attributes are treated as dates, and blank/unparseable values never match range operators. Nesting is limited to root group → optional sub-group → leaves (maximum depth 3).

Alternatives considered:
- Invent a new, richer rule DSL. Diverges from the filter vocabulary admins already know, and would need its own UI primitives.
- Reuse saved custom filters by reference. Couples assistants to filter records (rename/delete drift) and cannot express OR-over-AND trees.

Rationale: an audience must match the same contacts an equivalent segment would; aligning semantics with core filtering is both the least surprising behavior and the MIT-safe one.

### Engagement is gated when a conversation enters Pilot handling

`Pilot::Assistant#engages?(contact, conversation)` combines audience match and response-window availability. It is evaluated when the conversation's initial status is determined: a conversation whose assistant does not engage starts `open` (human queue) instead of `pending`, and only an engaged assistant becomes the AI assignee. Audience/window edits apply to *new* conversations; in-flight conversations are not re-gated per message.

Alternatives considered:
- Re-evaluate on every incoming message. More "live", but produces erratic mid-conversation takeovers/withdrawals (e.g. a contact attribute flip or the clock crossing business hours silences the AI mid-thread) and complicates handoff logic.
- Gate only in the sweep jobs. Leaves the assistant replying to conversations it should never have touched.

Rationale: creation-time gating is predictable, matches how `determine_conversation_status` already works, and keeps the evaluation cheap.

### Per-assistant inactivity settings with account-level fallback

`auto_resolve_mode` per assistant: `disabled` (never touch), `legacy` (time-based resolve), `evaluated` (LLM verdict → resolve or hand off). When unset, the assistant inherits `Account#pilot_auto_resolve_mode`; new assistants are stamped with the account value at creation. `auto_resolve_after` is the per-assistant idle threshold in minutes: integer, 5-minute steps, minimum 5, maximum 1440 (24 h), default 60; values are normalized to the nearest step on save. The existing `PILOT_AUTORESOLVE_IDLE_MINUTES` global remains only as a fallback when the assistant has no explicit value, preserving ops override behavior for existing installs. `send_inactivity_resolution_message` (default true) controls whether the customer sees a resolution message on inactivity resolution.

Alternatives considered:
- Keep the mode account-wide and add only the threshold per assistant. Two assistants with different service levels (e.g. a cautious evaluated assistant and a simple time-based one) remain impossible.
- Drop the global env override entirely. Breaks existing deployments that tuned it; unnecessary breakage for a fallback line of code.

Rationale: per-assistant control is the feature; account value and env override survive as fallbacks so nothing regresses on upgrade.

### Locked, idempotent sweep transitions

The sweep re-checks eligibility (still `pending`, still idle past the cutoff) inside a row lock immediately before transitioning, and again after the evaluated-mode LLM call returns. Transitions emit the same events/activities whether triggered by the time-based or evaluated path, and a conversation deleted or human-claimed mid-flight is skipped silently.

Alternatives considered:
- Rely on the existing re-check after evaluation only. Two overlapping sweep runs (or a sweep racing a human resolve) can double-post resolution messages.
- Optimistic status check without a lock. Still racy under concurrent Sidekiq workers.

Rationale: the upstream fix history for this area is entirely about races; row locks around the transition are the proven shape.

### One resolution-message service

A single service (`Pilot::Conversation::ResolutionMessageService`-equivalent, named per Konversio conventions at implementation time) decides whether and what to post: nothing when the toggle is off; the assistant's configured resolution message when present; otherwise the localized default; authored by the assistant in the account locale. Both the time-based and evaluated paths call it.

Alternatives considered:
- Keep message posting inline in `Custom::Pilot::AutoResolveService`/`ConversationResolver`. The toggle decision would be duplicated at every call site (and future ones, e.g. explicit resolve tools).

Rationale: message-or-silence is a policy decision and must have one home.

### Polymorphic AI assignee over the existing `assignee_agent_bot_id` column

Add `ai_assignee_type` (string) alongside the existing `assignee_agent_bot_id`; `Conversation#ai_assignee` is a polymorphic reader resolving `AgentBot` or `Pilot::Assistant`. Assigning an AI assignee clears the human assignee and sets status `pending`; assigning a human to a conversation with an AI assignee clears the AI assignee and opens the conversation (stamping `waiting_since`); `bot_handoff!` clears the AI assignee. `unassigned`/`assigned` scopes count both columns. The assignable-agents endpoint returns AI assignees only when the client opts in (`include_ai_assignees` param) so existing mobile clients are unaffected.

Alternatives considered:
- A separate `pilot_assistant_assignee_id` column. Every assignment touch point (scopes, push payload keys, filters, reporting) would need dual handling forever; polymorphism over one id column is what the schema already half-supports.
- Expose AI assignees in the payload unconditionally. Breaks older clients that assume every entry is a `User`.

Rationale: smallest schema change that makes AI ownership first-class everywhere assignment is reasoned about.

### Scenario/tool toggles are non-destructive and protective

Scenario index returns all scenarios (enabled flag exposed); toggling flips `enabled` without touching content; only enabled scenarios are registered at run time. Custom tools gain an enable/disable toggle on the Tools page; the API exposes how many **enabled** scenarios reference each tool, and disabling a referenced tool requires confirming a dialog that states that count. Disabled tools are excluded from every assistant's toolset and from scenario validation's available set — but a scenario that references a now-disabled tool keeps its stored reference (it simply has no live tool until re-enabled), so re-enabling restores behavior without data repair.

Alternatives considered:
- Block disabling a referenced tool outright. Hostile to ops (incident response needs a kill switch); warning achieves the awareness without the deadlock.
- Strip tool references from scenarios on disable. Destroys configuration; re-enable would not restore behavior.

Rationale: toggles are safety controls; they must be fast, reversible, and never silently destructive.

## Risks / Trade-offs

- **Audience evaluation cost** -> Evaluation is in-memory against an already-loaded contact/conversation; custom-attribute type lookups are memoized per evaluation. Gate only at creation time, never per message render.
- **Config bloat in `pilot_assistants.config`** -> Accept: config already carries messages and feature flags; the validator caps audience depth/size.
- **Account vs assistant mode confusion** -> UI must label the assistant-level default as inherited from account settings; API docs note the fallback order.
- **Partial rollout of `ai_assignee_type`** -> Column is additive and nullable; readers treat NULL type with a present id as the legacy `AgentBot` case.
- **needs investigation: whether the evaluated-mode handoff inside the System B sweep should trigger the inbox's out-of-office template** (upstream suppresses it for campaign conversations; Konversio's `Custom::Pilot::HandoffService` behavior on this path has not been confirmed) — resolve during implementation, defaulting to current Konversio behavior.

## Migration Plan

1. Add `conversations.ai_assignee_type` + composite index (additive, nullable; legacy rows read as `AgentBot`).
2. Ship model validations, audience services, per-assistant config accessors, and the resolution-message service with no behavior change until the engagement gate and sweep changes land behind them.
3. Update System B jobs to per-assistant mode/threshold and locked transitions; account mode and env override remain as fallbacks.
4. Ship API changes (assistant config permit + validation errors, scenario index, tool referenced-count, opt-in AI assignees), then the frontend settings pages, toggles, and assignee UI.
5. Rollback: all config keys are ignored when readers are reverted; `ai_assignee_type` column is additive and can be dropped last.

## Open Questions

- Should changing an assistant's audience/window re-gate currently `pending` conversations (e.g. reopen ones no longer targeted)? Current spec: no — creation-time only.
- Should the inactivity threshold upper bound (24 h) be configurable per installation, or is a fixed bound sufficient?
- Do conversation filters/reporting need an explicit "AI assignee" filter dimension in this change, or is assignee presence enough?
