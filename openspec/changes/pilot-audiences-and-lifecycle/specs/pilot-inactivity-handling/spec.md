## Capability: pilot-inactivity-handling

Per-assistant auto-resolve mode, inactivity threshold, and resolution-message toggle driving the System B idle-conversation sweep, with locked, idempotent status transitions.

---

## ADDED Requirements

### Requirement: Per-assistant auto-resolve mode with account fallback

Each `Pilot::Assistant` SHALL support an auto-resolve mode of `disabled` (the sweep never touches its conversations), `legacy` (idle pending conversations are resolved purely on elapsed time), or `evaluated` (an LLM verdict decides resolve vs hand off). When the assistant has no explicit mode, it SHALL inherit the account-level `pilot_auto_resolve_mode`; a newly created assistant SHALL be stamped with the account value at creation time. The mode MUST be validated for inclusion in the supported set.

#### Scenario: assistant inherits account mode when unset

- Given an account whose auto-resolve mode is `legacy`
- And an assistant with no explicit mode in its config
- When the effective mode is read
- Then it is `legacy`

#### Scenario: new assistant is stamped with the account value

- Given an account whose auto-resolve mode is `disabled`
- When a new assistant is created without a mode
- Then the assistant's stored mode is `disabled`

#### Scenario: assistant mode overrides account mode

- Given an account whose auto-resolve mode is `legacy`
- And an assistant explicitly configured as `evaluated`
- When the sweep processes that assistant's conversations
- Then the evaluated path is used

#### Scenario: unknown mode is rejected

- Given an assistant update with an unsupported mode value
- When the assistant is saved
- Then validation fails

---

### Requirement: Per-assistant inactivity threshold

Each assistant SHALL support an inactivity threshold in minutes controlling how long a `pending` conversation must be idle before the sweep acts on it. The value MUST be an integer between 5 minutes and 24 hours inclusive, MUST be normalized to the nearest 5-minute step on save, and SHALL default to 60 minutes when unset (falling back to the installation-level idle-minutes override when one is configured and the assistant has no explicit value).

#### Scenario: threshold drives the sweep cutoff

- Given an assistant with a 30-minute threshold
- And a `pending` conversation on its inbox idle for 45 minutes
- When the sweep runs
- Then the conversation is selected for processing

#### Scenario: conversation idle less than the threshold is untouched

- Given an assistant with a 30-minute threshold
- And a `pending` conversation idle for 10 minutes
- When the sweep runs
- Then the conversation is not selected

#### Scenario: out-of-range threshold is rejected

- Given an assistant update with a threshold below 5 minutes or above 1440
- When the assistant is saved
- Then validation fails

#### Scenario: threshold is normalized to five-minute steps

- Given an assistant update with a threshold of 47 minutes
- When the assistant is saved
- Then the stored threshold is a multiple of 5 within the allowed range

#### Scenario: unset threshold falls back to installation override then default

- Given an installation-level idle-minutes override of 90
- And an assistant with no explicit threshold
- When the sweep cutoff is computed
- Then 90 minutes is used
- And with no override configured, 60 minutes is used

---

### Requirement: Locked, idempotent sweep transitions

The System B sweep MUST re-verify, inside a database row lock immediately before transitioning, that each conversation is still `pending` and still idle past the assistant's cutoff. The evaluated path MUST additionally re-verify eligibility after the LLM evaluation returns (the customer may have replied during the call). Conversations deleted or transitioned by another actor mid-processing MUST be skipped without error. Per-run conversation volume SHALL remain capped so backlogs drain over multiple cycles.

#### Scenario: human resolves during sweep processing

- Given a conversation selected by the sweep
- And a human agent resolves it before the sweep transitions it
- When the sweep reaches the conversation
- Then the sweep leaves it resolved and posts no duplicate resolution message

#### Scenario: customer replies during evaluated-mode LLM call

- Given the sweep is evaluating an idle conversation
- And the customer sends a new message before the verdict returns
- When the verdict indicates completion
- Then the conversation is NOT resolved and remains `pending`

#### Scenario: conversation deleted mid-sweep is skipped

- Given a conversation selected by the sweep
- And the conversation is deleted before the sweep processes it
- When the sweep reaches it
- Then the sweep continues with the remaining conversations without raising

---

### Requirement: Inactivity resolution message toggle

Each assistant SHALL support a boolean setting (default on) controlling whether an inactivity resolution posts a customer-facing message. When on, the resolution message SHALL be posted as an outgoing assistant-authored message in the account's locale, using the assistant's configured resolution copy when present and otherwise a localized default. When off, the conversation SHALL still be resolved (with its activity/system record) but no customer-facing resolution message SHALL be posted.

#### Scenario: toggle on with custom message

- Given an assistant with the toggle on and a custom resolution message
- When an idle conversation is auto-resolved
- Then the custom message is posted, authored by the assistant

#### Scenario: toggle on without custom message

- Given an assistant with the toggle on and no custom resolution message
- When an idle conversation is auto-resolved
- Then the localized default resolution message is posted in the account's locale

#### Scenario: toggle off resolves silently

- Given an assistant with the toggle off
- When an idle conversation is auto-resolved
- Then the conversation status becomes `resolved`
- And no customer-facing resolution message is posted

---

### Requirement: Single resolution-message decision point

All inactivity resolution paths (time-based and evaluated) SHALL delegate the post-or-stay-silent decision and message selection to one shared service, so the toggle and the custom/default fallback cannot diverge between paths.

#### Scenario: evaluated and time-based paths produce identical message behavior

- Given an assistant with the toggle on and no custom message
- When one conversation is resolved via the time-based path and another via the evaluated path
- Then both receive the same localized default resolution message

---

### Requirement: Inactivity settings UI

The Pilot assistant settings MUST expose: the auto-resolve mode as mutually exclusive choices (displaying the inherited account default when unset), an inactivity-duration picker constrained to the 5-minute / 24-hour bounds and hidden when the mode is `disabled`, and the resolution-message toggle with its message editor.

#### Scenario: duration picker hidden when disabled

- Given the user selects the disabled mode
- Then the inactivity-duration picker is not shown

#### Scenario: saving persists all inactivity settings

- Given the user sets mode `evaluated`, a 45-minute threshold, and turns the message toggle off
- When the user saves
- Then the assistant update API receives all three config values
- And the sweep subsequently applies them
