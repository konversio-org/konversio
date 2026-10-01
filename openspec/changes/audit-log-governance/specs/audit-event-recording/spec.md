## Capability: audit-event-recording

Account-scoped recording of governance-relevant events: authentication activity, staff and team administration, account and channel configuration changes, and conversation/message removal. Entries are written to the core `audits` table through a dedicated `AuditLog` model, with actor identity denormalized at write time.

---

## ADDED Requirements

### Requirement: audit infrastructure in the core tree

The system SHALL record audit entries through a core `AuditLog` model backed by the existing `audits` table and SHALL configure the audited library to use that model for all recorded events.

#### Scenario: audit class is active

- Given the application has booted
- When any governed model records an audit entry
- Then the entry is persisted as an `AuditLog` record in the `audits` table

#### Scenario: audits table carries geolocation fields

- Given the migrations for this change have run
- Then the `audits` table has nullable `city`, `country`, and `country_code` columns
- And a composite index exists on `(associated_type, associated_id, created_at)`

---

### Requirement: actor identity denormalized at write time

Every audit entry MUST persist the acting user's email address at the moment the entry is written, so the trail remains readable after the user is renamed or deleted.

#### Scenario: entry records actor email

- Given an administrator with email "admin@example.com" updates an inbox setting
- When the audit entry is written
- Then the entry's username field contains "admin@example.com"

#### Scenario: entry survives user deletion

- Given an audit entry exists for a user who has since been deleted
- When the entry is read back
- Then the recorded username still shows the original email address

---

### Requirement: account scoping of entries

Every audit entry MUST be associated with the account it belongs to, so account-scoped listing never returns another account's entries. Entries for actions on the account record itself MUST also carry the account association.

#### Scenario: configuration change is account-associated

- Given an administrator updates account-level settings
- When the audit entry is written
- Then the entry's association points at that account

#### Scenario: listing is account-local

- Given two accounts each have audit entries
- When an administrator of the first account lists audit logs
- Then only entries associated with the first account are returned

---

### Requirement: governed event set

The system SHALL record audit entries for: user sign-in and sign-out; agent invitation and role changes; team creation, update, and deletion; team and inbox membership changes; inbox creation and configuration changes; webhook changes (excluding secret material); automation rule and macro changes; account settings changes; and conversation deletion. The system MUST NOT record entries for routine message traffic or other high-frequency events.

#### Scenario: webhook secret is not recorded

- Given an administrator updates a webhook
- When the audit entry is written
- Then the recorded changes do not include the webhook's secret value

#### Scenario: conversation deletion is recorded without attribute payload

- Given an administrator deletes a conversation
- When the audit entry is written
- Then the entry records the deletion action and the conversation's human-facing display number
- And the entry does not duplicate the conversation's full attribute set

#### Scenario: ordinary messages are not audited

- Given a conversation receives and sends messages
- Then no audit entries are created for those messages

---

### Requirement: sign-in and sign-out entries

On successful sign-in and on sign-out, the system SHALL record one audit entry per account the user belongs to, capturing the actor, the action, the request's IP address, and the request identifier. Recording MUST NOT be able to prevent or break authentication.

#### Scenario: user with two accounts signs in

- Given a user who belongs to two accounts signs in successfully
- Then two audit entries are created, one associated with each account
- And both entries carry the same request identifier and the sign-in IP address

#### Scenario: audit failure does not block sign-in

- Given the audit recording path raises an error during sign-in
- When the user submits valid credentials
- Then the sign-in still succeeds

---

### Requirement: message deletion entries

When a message is deleted through the conversation message API, the system SHALL record exactly one audit entry per deletion. The entry MUST capture a server-side snapshot identifying the deleted message's conversation (id and display number), inbox, and sender, plus the original body, taken before the deletion. Concurrent deletion attempts MUST NOT produce duplicate entries.

#### Scenario: deletion records a snapshot

- Given a message in a conversation with display number 1234
- When an administrator deletes the message
- Then an audit entry of action "destroy" exists for that message
- And the entry's recorded snapshot identifies conversation display number 1234, the inbox, and the sender

#### Scenario: already-deleted message is not re-audited

- Given a message that has already been soft-deleted
- When a second deletion request for the same message completes
- Then no additional audit entry is created

#### Scenario: concurrent deletes produce one entry

- Given two simultaneous deletion requests for the same message
- When both requests complete
- Then exactly one deletion audit entry exists for that message
