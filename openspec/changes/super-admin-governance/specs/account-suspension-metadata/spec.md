## Capability: account-suspension-metadata

Super admins record a category and reason when suspending an account, and Konversio keeps an append-only history of suspension events on the account, visible in the Super Admin dashboard.

---

## ADDED Requirements

### Requirement: Suspension categories are a fixed list

The system SHALL define a fixed set of suspension categories — `spam`, `non_payment`, `other` — exposed to super admins as human-readable labels when suspending an account.

#### Scenario: category select offers exactly the defined categories

- Given a super admin edits an account in the Super Admin dashboard
- When they set the status field to `suspended`
- Then the suspension category select offers exactly the defined categories plus an empty prompt
- And each option label comes from the backend i18n catalog

---

### Requirement: Metadata required when suspending an active account

When a super admin updates an account's status to `suspended` and the account is currently `active`, the system MUST require a valid suspension category and a non-empty suspension reason of at most 256 characters. Validation failure MUST leave the account unchanged and re-render the edit form with HTTP 422 and inline errors.

#### Scenario: suspending without metadata fails

- Given an active account
- When a super admin submits status `suspended` with a blank category and blank reason
- Then the response is HTTP 422
- And the account status remains `active`
- And no suspension event is recorded

#### Scenario: suspending with an unknown category fails

- Given an active account
- When a super admin submits status `suspended` with a category outside the defined list and a valid reason
- Then the response is HTTP 422
- And the account status remains `active`

#### Scenario: reason longer than 256 characters fails

- Given an active account
- When a super admin submits status `suspended` with a valid category and a 300-character reason
- Then the response is HTTP 422
- And the account status remains `active`

#### Scenario: suspending with valid metadata succeeds

- Given an active account
- When a super admin submits status `suspended` with category `spam` and reason "Outbound spam detected"
- Then the account status becomes `suspended`
- And a suspension event with category `spam`, reason "Outbound spam detected", and the current timestamp is appended to the account's suspension history

---

### Requirement: Suspension history is append-only per suspension

Each transition from `active` to `suspended` MUST append a new event (category, reason, ISO 8601 timestamp) to the account's suspension history. Saving an already-suspended account with changed metadata MUST update the most recent event in place rather than appending. History MUST be stored in the account's `internal_attributes` jsonb under `suspensions`.

#### Scenario: re-suspension appends a new event

- Given an account with one past suspension event that is currently `active`
- When a super admin suspends it again with a different category and reason
- Then the history contains two events
- And the newest event carries the newly submitted category, reason, and timestamp

#### Scenario: editing metadata while suspended updates the latest event

- Given a suspended account whose latest event has category `spam` and reason "first note"
- When a super admin saves the account still `suspended` with category `other` and reason "corrected note"
- Then the history still contains exactly one event
- And that event has category `other` and reason "corrected note"

#### Scenario: reactivating does not require metadata

- Given a suspended account
- When a super admin sets the status back to `active` without category or reason
- Then the account becomes `active`
- And the suspension history is unchanged

---

### Requirement: Legacy suspended accounts are grandfathered

An account that was suspended before this capability existed (status `suspended`, empty history) MAY be saved without suspension metadata. If metadata is provided for such an account, the system SHALL record it as the first history event.

#### Scenario: legacy suspended account saves without metadata

- Given a suspended account with an empty suspension history
- When a super admin saves the account with status still `suspended` and no category or reason
- Then the save succeeds
- And no history event is created

#### Scenario: legacy suspended account gains first event when metadata is provided

- Given a suspended account with an empty suspension history
- When a super admin saves it with status `suspended`, category `non_payment`, and a reason
- Then the history contains exactly one event with that category, reason, and the current timestamp

---

### Requirement: Suspension history is displayed in the Super Admin dashboard

The account show page in the Super Admin dashboard MUST display the suspension history as a table (suspended-at timestamp, category label, reason), newest event first, with an explicit empty state when no history exists.

#### Scenario: history table renders newest first

- Given an account with two suspension events recorded a week apart
- When a super admin views the account's show page
- Then both events are listed with localized timestamps and category labels
- And the most recent event appears first

#### Scenario: empty history shows an empty-state message

- Given an account with no suspension history
- When a super admin views the account's show page
- Then a "no suspension history" message is shown instead of a table

---

### Requirement: Suspension form fields follow the status select

In the Super Admin account form, the category and reason inputs MUST be hidden and disabled unless the status select is set to `suspended`, and MUST be marked required exactly when metadata would be validated (suspending an active account, an account with existing history, or once any metadata has been typed).

#### Scenario: fields hidden for active status

- Given a super admin edits an active account
- When the status select shows `active`
- Then the category and reason inputs are hidden and disabled

#### Scenario: fields become required when switching to suspended

- Given a super admin edits an active account
- When they change the status select to `suspended`
- Then the category and reason inputs become visible, enabled, and required

#### Scenario: submitted values survive a validation failure

- Given a super admin submits an invalid suspension (e.g. over-long reason)
- When the edit form is re-rendered with HTTP 422
- Then the category and reason inputs are pre-filled with the submitted values
