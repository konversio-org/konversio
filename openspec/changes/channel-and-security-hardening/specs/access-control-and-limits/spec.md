## Capability: access-control-and-limits

Expanded Rack::Attack throttle coverage, agent-bot endpoint allowlisting, admin authorization for dashboard apps and integration hooks, participant validation, builder-enforced agent/inbox limits with locking, per-account outbound e-mail limits, and super admin suspension metadata validation.

---

## ADDED Requirements

### Requirement: Widget API throttles are keyed per IP and website token

Conversation and message creation through the widget API MUST be throttled per (IP, website token) pair — using the same parameter precedence as the controller so a body token cannot fork the bucket — with defaults of 30 conversation creations and 60 message creations per minute. Widget contact updates (60/hour), widget page loads without an existing conversation token (200/hour), and transcript requests (5/hour) MUST be throttled per IP. Every widget throttle MUST be individually disableable and its limit overridable via environment variables, and the blanket widget-throttle kill switch MUST keep working.

#### Scenario: two sites behind one NAT get separate buckets

- Given two website tokens served from behind the same office IP
- When both widgets create conversations at 25/min each
- Then neither is throttled

#### Scenario: single-widget flood is throttled

- Given one website token
- When more than 30 conversation creations arrive from one IP in a minute
- Then subsequent requests are rejected with HTTP 429

#### Scenario: throttle can be disabled per endpoint

- Given the widget messages throttle is disabled via its environment switch
- When message creation exceeds the default limit
- Then requests are not throttled by that rule

---

### Requirement: Per-account throttles protect destructive and invitation endpoints

Conversation deletion MUST be throttled to 60/minute per account, agent creation (including bulk creation) to 100/day per account, and agent deletion to 50/day per account, each keyed on the account id in the path and overridable via environment variables.

#### Scenario: bulk agent invitation burst is capped

- Given an account
- When more than 100 agent-creation requests arrive in one day
- Then further requests receive HTTP 429

#### Scenario: limits are per account

- Given two accounts on one installation
- When one account exhausts its agent-creation budget
- Then the other account is unaffected

---

### Requirement: Reports drilldown is throttled per user

The reports drilldown endpoint MUST be throttled per individual user (web `uid` header, falling back to the API access token) combined with the account id, at one tenth of the reports API user-level limit (minimum 1) per minute.

#### Scenario: drilldown burst is throttled per user

- Given two users in one account
- When one user exceeds the drilldown limit
- Then only that user's subsequent drilldown requests receive HTTP 429

---

### Requirement: Agent bot tokens are restricted to an explicit endpoint allowlist

Access tokens owned by agent bots MUST be accepted only for an explicit allowlist of controller actions: conversation show, toggle status, toggle typing status, toggle priority, create, update, and custom attributes; message create; assignment create; and labels index/create. Any other endpoint MUST return 401 for bot tokens. Agent bot records MUST always be resolved through account-accessible scoping.

#### Scenario: bot reads a conversation

- Given an agent bot with a valid access token
- When it requests a conversation show
- Then the request succeeds

#### Scenario: bot is denied a non-allowlisted endpoint

- Given an agent bot with a valid access token
- When it requests account settings
- Then the response is 401 with a bot-authorization error

#### Scenario: cross-account agent bot cannot be attached to an inbox

- Given an agent bot owned by another account and not shared
- When an admin tries to set it on one of their inboxes
- Then the lookup fails as if the bot did not exist

---

### Requirement: Dashboard app management requires administrator authorization

Every dashboard app endpoint (index, show, create, update, destroy) MUST enforce authorization through a dashboard app policy that permits management only to administrators.

#### Scenario: agent is forbidden from managing dashboard apps

- Given a non-admin agent
- When they attempt to create or modify a dashboard app
- Then the response is 403

---

### Requirement: Conversation participants must be assignable agents

Adding conversation participants MUST validate that every added user id belongs to the conversation inbox's assignable agents; requests containing any other user id MUST fail with HTTP 422 and make no changes. Participant ids MUST be coerced to integers before comparison, and membership changes MUST be transactional.

#### Scenario: non-assignable user is rejected

- Given a user who is not a member of the conversation's inbox
- When they are included in a participants update
- Then the response is 422 with an invalid-participants error and no participant is added

#### Scenario: valid update adds and removes atomically

- Given a valid participants update adding one assignable agent and removing another
- When the request succeeds
- Then both changes are visible together and the unread-count-change event is dispatched when the unread features are enabled

---

### Requirement: Agent and inbox limits are enforced inside the builders under locks

Agent creation MUST check the account's agent limit inside an account-level lock and raise a limit error rendered as HTTP 402; bulk creation MUST evaluate the total count against remaining capacity under a single lock. Creating an inbox beyond the account's inbox limit MUST raise a dedicated inbox limit error. Creating a brand-new user as an agent MUST reserve outbound e-mail capacity for the invitation, failing with HTTP 429 when the account is over its e-mail limit.

#### Scenario: concurrent invitations cannot exceed the limit

- Given one remaining agent seat
- When two invitations are submitted concurrently
- Then exactly one succeeds and the other receives HTTP 402

#### Scenario: bulk create is all-or-nothing on capacity

- Given two remaining seats and a bulk request for five agents
- Then the request fails with HTTP 402 and no agents are created

#### Scenario: invitation over the e-mail limit fails with 429

- Given an account at its outbound e-mail limit
- When a new (never-seen) user is invited as an agent
- Then the response is 429 with an e-mail-limit error

---

### Requirement: Outbound e-mail is rate-limited per account

The system SHALL track outbound e-mails sent per account in a rolling Redis counter (25-hour TTL) and enforce a configurable limit (installation config `ACCOUNT_EMAILS_LIMIT`, with an account-level override and a built-in default). Capacity reservation for a batch MUST be atomic (check-and-increment in one Redis transaction). On self-hosted installs the limit applies whenever configured; it MUST NOT depend on any cloud-tier flag.

#### Scenario: limit blocks further sends

- Given an account that has sent its configured daily maximum
- When another outbound e-mail is attempted
- Then it is refused and the limit event is logged

#### Scenario: reservation is atomic under concurrency

- Given 10 remaining e-mail slots and two concurrent batches of 8
- Then exactly one batch is reserved

---

### Requirement: Super admin account suspension requires valid metadata

Setting an account's status to suspended in the super admin panel MUST require a suspension category from the account's allowed category list and a reason of at most 256 characters; invalid submissions MUST re-render the form with errors and HTTP 422, and accepted suspensions MUST be recorded in the account's suspension history.

#### Scenario: suspension without a reason is rejected

- Given a super admin suspending an account
- When no reason is supplied
- Then the form is re-rendered with a validation error and the account is unchanged

#### Scenario: suspension is recorded in history

- Given a valid suspension
- When it is saved
- Then the account's suspension history gains an entry with category, reason, and timestamp
