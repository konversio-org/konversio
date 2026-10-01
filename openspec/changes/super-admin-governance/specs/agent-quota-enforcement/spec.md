## Capability: agent-quota-enforcement

Race-safe enforcement of the per-account agent seat limit for single and bulk invitations, with invitation emails counted against the account's daily outbound email limit.

---

## ADDED Requirements

### Requirement: Agent limit is enforced inside AgentBuilder under a row lock

`AgentBuilder#perform` MUST check the account's agent quota and create the user/account-user records atomically while holding a database row lock on the account. When `account_users.count` has reached `usage_limits[:agents]`, the builder MUST raise `AgentBuilder::LimitExceededError` and MUST NOT create any user or account-user record.

#### Scenario: invitation within quota succeeds

- Given an account with 3 account users and an agent limit of 5
- When an admin invites a new agent
- Then the user and account-user records are created
- And no error is raised

#### Scenario: invitation at quota is rejected

- Given an account with 5 account users and an agent limit of 5
- When an admin invites a new agent
- Then `AgentBuilder::LimitExceededError` is raised
- And no user or account-user record is created

#### Scenario: concurrent invitations cannot exceed the quota

- Given an account with 4 account users and an agent limit of 5
- When two invitations for different emails are processed concurrently
- Then exactly one of them succeeds
- And the other raises `AgentBuilder::LimitExceededError`
- And the account ends with exactly 5 account users

---

### Requirement: Agents API returns 402 when the quota is exhausted

`POST /api/v1/accounts/:account_id/agents` and the bulk invitation endpoint MUST respond with HTTP 402 and the limit message when the invitation would exceed the account's agent quota.

#### Scenario: single create at limit returns 402

- Given an account at its agent limit
- When an admin posts a new agent
- Then the response is HTTP 402
- And the body explains the account limit was exceeded

#### Scenario: bulk create larger than remaining capacity returns 402 and creates nothing

- Given an account with 2 remaining agent seats
- When an admin bulk-invites 3 emails
- Then the response is HTTP 402
- And no users or account users are created for any of the 3 emails

---

### Requirement: Bulk invitation is atomic per account and tolerant of bad emails

Bulk invitation MUST take the account row lock once, pre-check the email count against the remaining capacity, and then create each agent inside the same lock. An email that fails record validation (e.g. malformed address) MUST be logged and skipped without failing the whole batch. A daily-email-limit failure MUST abort the batch and surface the error to the caller.

#### Scenario: one invalid email does not fail the batch

- Given an account with sufficient seats and email capacity
- When an admin bulk-invites "teammate@example.com" and "not-an-email"
- Then the valid email results in an invited agent
- And the invalid email is logged and skipped
- And the response is HTTP 200

#### Scenario: daily email limit aborts the batch

- Given an account whose daily outbound email limit is exhausted
- When an admin bulk-invites 2 new emails
- Then the response is HTTP 429
- And neither user is created

---

### Requirement: Invitation emails reserve daily email capacity before commit

When an invitation creates a *new* user, the system MUST reserve one unit of the account's daily outbound email capacity inside the creation transaction and MUST send the confirmation instructions only after the transaction completes. If capacity cannot be reserved, the system MUST raise `CustomExceptions::Account::EmailLimitExceeded` and roll back the user creation. Re-inviting an existing (even unconfirmed) user MUST NOT reserve capacity or resend instructions. On deployments where the daily email limit is disabled, reservation MUST be a no-op success.

#### Scenario: new-user invitation reserves capacity and sends after commit

- Given an account below its daily email limit
- When an admin invites an email with no existing user
- Then one unit of daily email capacity is consumed
- And the confirmation instructions email is enqueued after the records are committed

#### Scenario: exhausted email limit rolls back the invitation

- Given an account at its daily outbound email limit
- When an admin invites an email with no existing user
- Then `CustomExceptions::Account::EmailLimitExceeded` is raised
- And no user or account-user record is created
- And no confirmation email is enqueued

#### Scenario: existing user consumes no capacity

- Given an existing unconfirmed user who is not a member of the account
- When an admin invites that user's email to the account
- Then the account-user record is created
- And no daily email capacity is consumed
- And no confirmation email is enqueued

#### Scenario: reservation is atomic under concurrency

- Given an account with exactly 1 unit of daily email capacity remaining
- When two invitations for new users race
- Then at most one unit of capacity is granted
- And at most one confirmation email is enqueued

---

### Requirement: Seat counting uses account memberships

Remaining agent capacity MUST be computed as `usage_limits[:agents]` minus the number of `account_users` records (seats), not any derived or eager-loaded user relation.

#### Scenario: deleted-user edge does not inflate capacity

- Given an account whose user records were partially removed but account-user memberships remain
- When remaining capacity is computed
- Then it reflects the count of account-user memberships
