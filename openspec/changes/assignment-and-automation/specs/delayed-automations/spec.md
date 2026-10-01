## Capability: delayed-automations

Automation rules can fire a configurable delay after a qualifying event, and only if the conversation is still in the qualifying state when the delay elapses. Delayed rules record a pending execution at match time; a periodic sweep re-checks and runs them at due time. Ports upstream Chatwoot v4.17.x–v4.18.0 (MIT), including the v4.18.0 condition set for conversation-level delayed rules.

---

## ADDED Requirements

### Requirement: execution_delay on automation rules

Automation rules SHALL support an optional `execution_delay` in whole minutes, constrained to 10 through 43,200 (10 minutes to 30 days). A rule without `execution_delay` MUST execute immediately on match, exactly as before. The value MUST be exposed in the automation rule API response.

#### Scenario: rule without delay executes immediately

- Given an active automation rule with no `execution_delay`
- When a matching event occurs
- Then the rule's actions execute immediately

#### Scenario: delay must be within range

- Given an automation rule with `execution_delay` of 5 minutes, or more than 43,200 minutes
- When the rule is saved
- Then validation fails on `execution_delay`

#### Scenario: delay must be a whole number of minutes

- Given an automation rule with a non-integer `execution_delay`
- When the rule is saved
- Then validation fails on `execution_delay`

---

### Requirement: condition restrictions for delayed rules

Delayed automation rules MUST NOT use `attribute_changed` filter operators, because the fire-time re-check cannot reconstruct changed attributes. Delayed rules on conversation-level events (e.g. conversation created/updated) MAY only filter on conversation status and inbox; all other conversation attributes are rejected, because episodes are keyed on the status clock and mutable attributes would collapse distinct waiting periods into one episode. Delayed rules on message-created events MAY use any condition.

#### Scenario: attribute_changed condition is rejected with a delay

- Given an automation rule with `execution_delay` set and a condition using the `attribute_changed` filter operator
- When the rule is saved
- Then validation fails with an error that delayed execution cannot be used with attribute-changed conditions

#### Scenario: status condition is allowed on a conversation-level delayed rule

- Given a conversation_updated automation rule with `execution_delay` of 60 minutes and a condition on conversation status
- When the rule is saved
- Then the rule is valid

#### Scenario: inbox condition is allowed on a conversation-level delayed rule

- Given a conversation_updated automation rule with `execution_delay` of 60 minutes and a condition on inbox
- When the rule is saved
- Then the rule is valid

#### Scenario: other conversation attributes are rejected on a conversation-level delayed rule

- Given a conversation_updated automation rule with `execution_delay` set and a condition on any conversation attribute other than status or inbox (e.g. assignee, team, priority, labels)
- When the rule is saved
- Then validation fails with an error that delayed execution only supports status and inbox conditions for conversation-level events

#### Scenario: message-created delayed rules are unrestricted

- Given a message_created automation rule with `execution_delay` set and conditions on message content and message type
- When the rule is saved
- Then the rule is valid

---

### Requirement: pending execution lifecycle

A matching delayed rule SHALL record a pending execution instead of acting immediately, identified by an episode key unique per rule, conversation, and qualifying stretch of state. At due time a periodic sweep MUST re-validate the pending execution before running actions, and MUST skip (with a recorded reason) when the rule is gone or inactive, the conversation is gone, the episode has moved on (state changed since arming), or the conditions no longer match. A pending execution that comes due while its account's feature flag is off MUST pause rather than fire, resuming when the flag is re-enabled.

#### Scenario: matching event arms a pending execution

- Given an active conversation_updated rule with `execution_delay` of 60 minutes and a status condition
- And the account has the delayed automations feature enabled
- When a conversation changes into the matching status
- Then a pending execution is recorded with a due time 60 minutes after the status change
- And no actions execute immediately

#### Scenario: actions run at due time when state still matches

- Given a pending execution whose due time has passed
- And the conversation is still in the state that armed it
- And the rule's conditions still match
- When the sweep processes the pending execution
- Then the rule's actions execute once
- And the pending execution is marked executed

#### Scenario: episode moved — actions are skipped

- Given a pending execution armed by a status change
- And the conversation's status changed again before the due time
- When the sweep processes the pending execution
- Then the pending execution is marked skipped with the episode-moved reason
- And no actions execute

#### Scenario: conditions no longer match — actions are skipped

- Given a pending execution whose episode is still current
- And the rule's conditions no longer match the conversation at due time
- When the sweep processes the pending execution
- Then the pending execution is marked skipped with the conditions-changed reason

#### Scenario: conversation created in the target status also arms

- Given an active conversation_updated rule with `execution_delay` and a status condition
- When a conversation is created directly in the matching status
- Then a pending execution is armed, keyed to the same episode as a later status update would produce

#### Scenario: flag off pauses instead of firing

- Given a pending execution whose due time has passed
- And the account's delayed automations feature is disabled
- When the sweep runs
- Then the pending execution remains pending
- And no actions execute

#### Scenario: backlog after downtime is bounded

- Given a pending execution whose due time is more than 3 days in the past
- When the sweep processes it
- Then the pending execution is marked skipped with the expired reason

---

### Requirement: rule changes discard armed executions

When a delayed rule's execution configuration changes — its active flag, delay, event, conditions, or actions — all of its armed (pending or claimed-but-not-acting) pending executions MUST be discarded, so a rule that was edited or turned off does not later fire actions the admin meant to stop. Pending executions already running their actions MUST be left to finish.

#### Scenario: deactivating a rule discards its armed executions

- Given a delayed rule with armed pending executions
- When the rule is deactivated
- Then the armed pending executions are deleted

#### Scenario: editing conditions discards armed executions

- Given a delayed rule with armed pending executions
- When the rule's conditions are changed
- Then the armed pending executions are deleted
- And new pending executions arm on the next matching event

---

### Requirement: execution_delay is gated by the account feature flag

The `execution_delay` attribute MUST only be writable through the automation rules API when the account has the delayed automations feature enabled. Requests passing `execution_delay` while the flag is off MUST be rejected with an unprocessable-entity error, and cloning a delayed rule while the flag is off MUST be refused rather than silently producing an instant rule.

#### Scenario: writing execution_delay with flag off is rejected

- Given an account without the delayed automations feature
- When a create or update request includes `execution_delay`
- Then the API responds 422 with an error that delayed automations are not enabled for the account

#### Scenario: cloning a delayed rule with flag off is refused

- Given a delayed automation rule
- And the account's delayed automations feature is disabled
- When the rule is cloned
- Then the API refuses the clone with the delayed-automations error

#### Scenario: writing execution_delay with flag on succeeds

- Given an account with the delayed automations feature enabled
- When a rule is created with `execution_delay: 240`
- Then the rule is saved with `execution_delay` of 240
- And the rule API response includes `execution_delay`

---

### Requirement: delayed run configuration in the automation UI

The automation rule form MUST let the user choose between immediate and delayed execution, and for delayed execution pick a wait duration within the allowed range. The delayed option MUST only be offered when the account has the delayed automations feature enabled. Rule listings SHOULD display the configured delay in a compact human-readable form (minutes, hours, or days).

#### Scenario: delayed option hidden without the flag

- Given an account without the delayed automations feature
- When the automation rule form opens
- Then no delayed-execution option is shown

#### Scenario: configuring a delayed rule

- Given an account with the delayed automations feature
- When the user selects delayed execution with a 4-hour wait and saves
- Then the rule is saved with `execution_delay` of 240

#### Scenario: editing a delayed rule restores the wait state

- Given an existing rule with `execution_delay` of 1440
- When the rule edit form opens
- Then delayed execution is pre-selected with a 1-day wait
