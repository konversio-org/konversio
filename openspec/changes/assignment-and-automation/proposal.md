## Why

Three upstream improvements (all MIT-licensed Chatwoot core code) close real operational gaps in assignment and automation:

1. **Stale auto-assignment (v4.16.0).** Assignment policies run bulk auto-assignment over every open, unassigned conversation in an inbox — including conversations that have been idle for weeks or months. Agents get assigned dead backlog nobody will act on, which pollutes their fair-distribution quota and buries live work. There is no way to exclude stale conversations from automatic assignment.
2. **Delayed automations fire on the wrong conditions (v4.18.0).** Upstream's delayed automation rules (fire N minutes after a qualifying event, only if the conversation is still in that state) must restrict which conditions a delayed rule may use: the fire-time re-check cannot reconstruct `attribute_changed` conditions, and conversation-level episodes key on the status clock, so mutable conversation attributes would collapse distinct waiting periods into one. Upstream v4.18.0 widened the allowed condition set to include inbox alongside status. Konversio's fork base (v4.13.0) predates delayed automations entirely, so the whole delayed-rule capability — including its condition constraints — is missing.
3. **Automation filters mangle values containing commas (v4.17.1).** The automation rule editor round-trips multi-value text conditions (e.g. "message contains") through a comma-joined string: on save `filterQueryGenerator` splits `content` values on `,`, and on edit the values are re-joined with `,`. Any value that itself contains a comma is silently split into two conditions, changing what the rule matches.

## What Changes

- Add nullable `exclude_older_than_hours` (integer, default 168 = 7 days) to `assignment_policies`; `nil` disables the age exclusion. Validate integer > 0 when present.
- `AutoAssignment::AssignmentService` excludes conversations whose `last_activity_at` is older than the policy's threshold (or the 168-hour default when the inbox has no policy) from bulk auto-assignment. `last_activity_at` is used so reopened/active conversations are not excluded by their original `created_at`.
- Expose `exclude_older_than_hours` in the assignment policy API (strong params + jbuilder) and the assignment policy form UI (duration input, minutes↔hours bridge).
- Port delayed automation rules: nullable `execution_delay` (minutes, 10..43_200) on `automation_rules`, gated by a `delayed_automations` account feature flag, with episode-keyed `automation_rule_pending_executions`, a periodic sweep job, and fire-time re-checks.
- Enforce delayed-rule condition constraints at the model layer: no `attribute_changed` conditions with a delay; conversation-level events may only filter on `status` and `inbox_id` (the v4.18.0 "additional conditions"); `message_created` rules are unrestricted.
- Discard armed pending executions when a rule's execution config (active flag, delay, event, conditions, actions) changes.
- Gate `execution_delay` in the automation rules API (reject when the account flag is off, including on clone) and expose it in the jbuilder partial.
- Replace the comma-joined `comma_separated_plain_text` condition input with a chip-based `multi_text` input that keeps values as an array end-to-end; remove the comma split/join special case for `content` in `filterQueryGenerator` / `useEditableAutomation`.

## Capabilities

### New Capabilities
- `assignment-policy-age-exclusion`: Assignment policies can exclude stale conversations (no activity within a configurable age threshold) from automatic assignment.
- `delayed-automations`: Automation rules can fire a configurable delay after a qualifying event, only if the conversation is still in the qualifying state at fire time, with model-enforced restrictions on which conditions a delayed rule may use.

### Modified Capabilities
- `automation-condition-multi-value-input`: Multi-value text conditions in automation rules (and shared filter rows) keep values as arrays instead of round-tripping through comma-joined strings, so values containing commas match literally.

## Impact

- `assignment_policies` table (new nullable column, migration required)
- `AssignmentPolicy` model, `AutoAssignment::AssignmentService`, assignment policies controller + jbuilder, `AgentAssignmentPolicyForm.vue`
- `automation_rules` table (new nullable `execution_delay` column), new `automation_rule_pending_executions` table with a unique episode index; `conversations.status_changed_at` column (upstream `db/migrate/20260709060100`)
- `AutomationRule` model (validations, stale-execution discard), `AutomationRuleListener`, automation rules controller + jbuilder
- New `AutomationRulePendingExecution` model, `AutomationRules::TriggerPendingExecutionsJob` (scheduled sweep), `AutomationRules::ProcessPendingExecutionJob`
- `config/features.yml` + `Featurable` (`delayed_automations` flag — Konversio's jsonb flags, not upstream's bitset extension column)
- Automation settings UI: `AutomationRuleForm.vue`, new run-type/wait-condition components, `AutomationRuleRow.vue`, i18n (`en.json` only)
- Filter condition UI: `components-next/filter/ConditionRow.vue`, new `MultiTextInput.vue`, `useEditableAutomation.js`, `filterQueryGenerator.js`, automation `constants.js`
