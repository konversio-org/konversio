## Capability: assignment-policy-age-exclusion

Assignment policies can exclude stale conversations — those with no recent activity — from automatic assignment, so bulk auto-assignment only distributes live work. Ports upstream Chatwoot v4.16.0 (MIT).

---

## ADDED Requirements

### Requirement: exclude_older_than_hours stored on AssignmentPolicy

Assignment policy records SHALL store an optional `exclude_older_than_hours` integer (hours) defaulting to 168 (7 days). A nil value MUST disable the age exclusion for that policy. When present, the value MUST be an integer greater than 0.

#### Scenario: default is 168 hours

- Given a new assignment policy is created without an explicit threshold
- Then `exclude_older_than_hours` is 168

#### Scenario: nil disables the exclusion

- Given an assignment policy with `exclude_older_than_hours` set to nil
- When the policy is saved
- Then the policy is valid
- And no age exclusion is applied for inboxes using that policy

#### Scenario: non-positive values are rejected

- Given an assignment policy with `exclude_older_than_hours` set to 0 or a negative number
- When the policy is saved
- Then validation fails

#### Scenario: threshold is configurable via API

- Given an assignment policy exists
- When the policy is updated via the assignment policies API with `exclude_older_than_hours: 48`
- Then `exclude_older_than_hours` equals 48
- And the policy API response includes `exclude_older_than_hours`

---

### Requirement: bulk auto-assignment skips stale conversations

When bulk auto-assignment selects unassigned open conversations for an inbox, it MUST exclude conversations whose `last_activity_at` is older than the applicable threshold: the inbox's assignment policy `exclude_older_than_hours` when a policy exists and the value is present, otherwise the default of 168 hours. The age comparison MUST use `last_activity_at`, not `created_at`, so reopened or recently active old conversations remain assignable.

#### Scenario: stale conversation is excluded

- Given an inbox with an assignment policy whose `exclude_older_than_hours` is 168
- And an open, unassigned conversation whose `last_activity_at` is 10 days ago
- When bulk auto-assignment runs for the inbox
- Then the conversation is not assigned

#### Scenario: recently active old conversation is still assigned

- Given an inbox with an assignment policy whose `exclude_older_than_hours` is 168
- And an open, unassigned conversation created 30 days ago whose `last_activity_at` is 1 hour ago
- When bulk auto-assignment runs for the inbox
- Then the conversation is eligible for assignment

#### Scenario: inbox without a policy uses the default threshold

- Given an inbox with no assignment policy
- And an open, unassigned conversation whose `last_activity_at` is 10 days ago
- When bulk auto-assignment runs for the inbox
- Then the conversation is not assigned

#### Scenario: nil threshold assigns everything

- Given an inbox with an assignment policy whose `exclude_older_than_hours` is nil
- And an open, unassigned conversation whose `last_activity_at` is 30 days ago
- When bulk auto-assignment runs for the inbox
- Then the conversation is eligible for assignment

---

### Requirement: exclusion threshold field in the assignment policy form

The assignment policy form MUST expose the age exclusion as an optional duration field that reads and writes `exclude_older_than_hours`, defaulting to 168 hours (7 days) for new policies.

#### Scenario: form shows the current threshold

- Given an assignment policy with `exclude_older_than_hours` of 168
- When the policy edit form opens
- Then the exclusion field displays 7 days

#### Scenario: saving a custom threshold

- Given the user sets the exclusion field to 2 days
- When the form is saved
- Then the policy API is called with `exclude_older_than_hours: 48`

#### Scenario: non-day thresholds are not floored on display

- Given an assignment policy with `exclude_older_than_hours` of 25
- When the policy edit form opens
- Then the exclusion field displays 25 hours, not 1 day
