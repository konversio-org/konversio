## Context

All three items are upstream Chatwoot **core-tree (MIT)** work. Verbatim porting is legal and preferred where Konversio's fork base matches upstream v4.13.0; deviations are only needed where Konversio has already diverged (feature flags, frontend conventions). Reference diffs: `git -C /tmp/chatwoot-upstream diff v4.13.0 v4.18.0 -- <paths>`.

Upstream state at v4.18.0 (the target):

- **Stale assignment exclusion** — `assignment_policies.exclude_older_than_hours` (integer, default 168, nullable; nil disables). `AutoAssignment::AssignmentService#unassigned_conversations` applies `last_activity_at >= hours.hours.ago` when the threshold is present, falling back to `AssignmentPolicy::DEFAULT_EXCLUDE_OLDER_THAN_HOURS` (168) when the inbox has no policy. Exposed in the assignment policy API and the policy form via `DurationInput`.
- **Delayed automations** — `automation_rules.execution_delay` (minutes, 10..43_200, nullable) behind a `delayed_automations` account feature flag. Matching delayed rules record an `AutomationRulePendingExecution` (episode-keyed, unique per rule+conversation+episode) instead of acting immediately; `AutomationRules::TriggerPendingExecutionsJob` sweeps due rows and `AutomationRules::ProcessPendingExecutionJob` re-checks episode currency and conditions at fire time before running actions. Condition constraints: delayed rules may not use `attribute_changed` conditions; conversation-level events may only filter on `status` and `inbox_id` (`AutomationRule::DELAYED_CONVERSATION_ATTRIBUTES`); `message_created` rules are unrestricted. Conversation creation also arms delayed `conversation_updated` rules (a conversation created in the target status has been "in this status" since creation).
- **Comma fix** — the `content` (and similar multi-value text) condition stops round-tripping through `values.join(',')` / `values.split(',')`; a new `multi_text` input type keeps values as an array in the editor, payload, and API.

## Goals / Non-Goals

**Goals:**

- Port the stale-conversation age exclusion for assignment policies end-to-end (migration → model → service → API → form UI).
- Port delayed automations end-to-end, including the v4.18.0 condition support (`status` + `inbox_id` for conversation-level events) and all fire-time safety re-checks.
- Port the comma-safe multi-value condition input.
- Keep Konversio divergences: jsonb feature flags (no `feature_flags_ext_1` bitset), `components-next` UI conventions, `en`-only i18n.

**Non-Goals:**

- The unrelated v4.16–v4.18 auto-assignment concurrency work in the same files (per-inbox in-flight Redis gate, atomic `claim_and_assign`) — not part of these changelog items.
- The unrelated `FilterService` refactor in the same diff (label query rebuild, `set_count_for_all_conversations` single-scan, `days_before` bounds) except where the comma fix touches it.
- Automation analytics, execution logs UI, or admin surfacing of pending executions.
- Changing immediate (non-delayed) automation semantics in any way.

## Decisions

### Port the stale-exclusion threshold verbatim, keyed on `last_activity_at`

Upstream stores hours on the policy and filters `conversations.last_activity_at >= threshold.hours.ago` inside `unassigned_conversations`. A policy-less inbox still gets the 168-hour default; `nil` on a policy disables exclusion entirely.

Alternatives considered:
- Exclude on `created_at` instead. Rejected: a reopened old conversation would be permanently excluded despite being active.
- No default when there is no policy (assign everything, as today). Rejected: upstream deliberately applies the default policy-less too, and silently changing behavior per-inbox-type is more surprising than one uniform default.

Rationale: verbatim port keeps parity and the semantics are sound. One caveat to verify during implementation: applying a default exclusion to policy-less inboxes changes behavior for inboxes that never opted into assignment policies — confirm this matches the intended product behavior for Konversio, and call it out in release notes if kept.

### Store `execution_delay` in minutes on the rule; keep upstream's range

Upstream validates `execution_delay` as an integer in `10..43_200` minutes (10 minutes to 30 days), nullable. Port as-is, including `EXECUTION_DELAY_RANGE`.

Alternatives considered:
- Seconds for finer granularity. Rejected: upstream's minimum of 10 minutes is deliberate (the sweep runs on a schedule; sub-minute delays would need a different dispatch mechanism), and parity keeps the port reviewable.

### Delayed-rule condition constraints enforced on the model, not just the UI

Upstream enforces both constraints as `AutomationRule` validations (`execution_delay_supported_conditions`, `execution_delay_supported_event`) so API clients cannot create invalid delayed rules even if the UI is bypassed. Port both, plus `DELAYED_CONVERSATION_ATTRIBUTES = %w[status inbox_id]` (the v4.18.0 set — the "additional conditions" item is `inbox_id` joining `status`).

needs investigation: the shallow upstream clone only carries the v4.13.0 and v4.18.0 tags, so the exact pre-v4.18.0 allowed set cannot be diffed; the spec targets the final v4.18.0 state. If intermediate-tag behavior matters for migration of existing rules, fetch the v4.17.x tags and diff `app/models/automation_rule.rb` between them.

### Feature flag via Konversio's jsonb `Featurable`, not upstream's bitset extension

Upstream put `delayed_automations` in a new `feature_flags_ext_1` bitset column because its `feature_flags` bigint was full. Konversio replaced the bitset with a jsonb `feature_flags` hash (`app/models/concerns/featurable.rb`), so the port simply appends a `delayed_automations` entry to `config/features.yml` (`enabled: false`) — no migration, no extension column, no bit-position bookkeeping.

Rationale: porting the bitset machinery would re-introduce a constraint Konversio deliberately removed. Behavior stays identical: `account.feature_enabled?('delayed_automations')` gates arming, API writes, and the sweep's `for_enabled_accounts` scope.

### Discard armed executions on rule config change; refuse unsafe clones

Port upstream's `after_update :discard_stale_pending_executions` (fires when active/delay/event/conditions/actions change; deletes pending + processing rows, leaves executing rows alone) and the controller behavior: `execution_delay` is stripped from permitted params when the flag is off, explicit `execution_delay` params get a 422, and cloning a delayed rule with the flag off is refused rather than silently cloning an instant rule.

Rationale: these are the semantics that make delayed rules safe to operate; dropping them would port the feature without its guardrails.

### Chip-based `multi_text` input replaces comma-joined strings

Port upstream's `components-next/filter/inputs/MultiTextInput.vue` (array v-model, Enter/blur commits a chip) and the `multi_text` input type; update `ConditionRow.vue`, automation `constants.js` (`content` uses `multi_text`), `useEditableAutomation.js` (keep `values` as `[...condition.values]`), and remove the `attribute_key === 'content'` split special case in `filterQueryGenerator.js`.

Alternatives considered:
- Escape/quote commas inside the joined string. Rejected: invented wire format, diverges from upstream, and every consumer must agree on the escaping.
- Keep join/split but only on the client. Rejected: the split is exactly the bug; values must be arrays end-to-end.

## Risks / Trade-offs

- **Behavior change for policy-less inboxes** -> The 168-hour default applies even without a policy; document in release notes and flag for product sign-off during implementation.
- **Sweep backlog after downtime** -> Upstream bounds replay with a 3-day due window (`DUE_WINDOW`) and reschedules rows paused by the account flag; port those constants with the jobs, not as follow-ups.
- **Existing automation rules with commas in values** -> Rules saved under the old split behavior already hold fragmented values in the DB; the new UI will display each fragment as its own chip. A data repair is out of scope; needs investigation: whether a migration to re-join known-fragmented `content` conditions is worth shipping.
- **`conversations.status_changed_at` backfill** -> Upstream deliberately does not backfill; conversations predating the column arm on their next status change. Porting the migration as-is inherits this (old conversations never instantly overdue on the first sweep).

## Migration Plan

1. Migrations first: `exclude_older_than_hours` on `assignment_policies`; `execution_delay` on `automation_rules`; `status_changed_at` on `conversations`; `automation_rule_pending_executions` with the unique episode index and the `(status, updated_at)` index.
2. Backend: models, listener, services, jobs, controllers, jbuilders; register the sweep on the scheduled jobs queue.
3. Frontend: policy form duration input; automation run-type/wait UI; `multi_text` condition input.
4. Rollback: feature flag off stops arming and sweeping (pending rows pause, they do not fire); columns are additive and can remain.

## Open Questions

- Should `delayed_automations` ship enabled for existing accounts, or stay opt-in per account (upstream default: `enabled: false`)? Proposal keeps upstream's opt-in default.
- Does Konversio want the automation settings UI's new run-type selector copy adapted to Konversio product language, or ported verbatim? Verbatim is legal (MIT); decide during implementation.
