## Why

Super admins can suspend an account today, but nothing records *why*. There is no category, no reason, and no history — once an account is reactivated, all institutional knowledge of the suspension is gone. This makes abuse enforcement, billing disputes, and support escalations dependent on out-of-band notes.

Separately, the account-level usage limits that super admins configure are enforced weakly:

- The agent quota is checked in the controller *before* creation, with no lock — two concurrent invitations can both pass the check and exceed the limit (a check-then-act race). Bulk invitation validates the count up front but each create can still race, and invitation emails are sent inside the transaction without counting against the account's daily outbound email limit.
- The inbox limit is only enforced in `Api::V1::InboxesHelper#validate_limit` on the standard `inboxes#create` path. Inboxes created through channel-specific flows (Facebook/Instagram callbacks, Twilio, WhatsApp embedded signup) bypass the check entirely.

Upstream Chatwoot addressed these in v4.16.1 ("agent quotas" security fix) and v4.16.2 ("Super Admin account suspension metadata", "agent invitation limit", "account limits" hardening). All of the relevant upstream code lives in the MIT-licensed core tree and can be ported directly.

## What Changes

- **Suspension metadata**: When a super admin sets an account's status to `suspended`, require a suspension category (from a fixed list) and a free-text reason (max 256 chars). Persist each suspension as an event (category, reason, timestamp) in a history list on the account, and display that history on the Super Admin account page. Re-suspending an active account appends a new event; editing metadata while already suspended updates the latest event instead.
- **Agent quota enforcement**: Move the agent-limit check from the agents controller into `AgentBuilder`, executed under a database row lock on the account so concurrent invitations cannot exceed the quota. Make bulk invitation atomic per account (count pre-check under the same lock) and return HTTP 402 with a clear error when the quota is exhausted.
- **Agent invitation email limit**: Count invitation (confirmation) emails against the account's daily outbound email rate limit by reserving capacity before the user record is committed, and send the invitation only after the transaction commits. Existing unconfirmed users re-invited do not consume email capacity again.
- **Account resource limits**: Enforce the inbox limit at the `Inbox` model level (before create) so *every* inbox creation path is covered, raising a dedicated exception that renders HTTP 402. Centralize rescue handling for limit exceptions in `RequestExceptionHandler`.

## Capabilities

### New Capabilities
- `account-suspension-metadata`: Super Admin captures a category and reason when suspending an account, stored as an append-only suspension history on the account and displayed in the Super Admin dashboard.
- `agent-quota-enforcement`: Race-safe agent quota checks in `AgentBuilder` (single and bulk invitation), plus daily email-limit reservation for invitation emails.
- `account-resource-limits`: Model-level inbox limit enforcement covering all creation paths, with a shared limit-exception type and centralized HTTP 402 handling.

### Modified Capabilities
None.

## Impact

- `app/models/account.rb` (suspension categories constant, virtual attributes, `suspension_history` reader)
- `app/controllers/super_admin/accounts_controller.rb` (validation + history persistence on update)
- `app/dashboards/account_dashboard.rb` (new status field, suspension history on show page, permitted attributes)
- New Administrate fields: `app/fields/account_status_field.rb`, `app/fields/suspension_history_field.rb` and their views
- `app/javascript/entrypoints/superadmin.js` (conditional show/require of suspension fields)
- `app/builders/agent_builder.rb`, `app/controllers/api/v1/accounts/agents_controller.rb` (quota lock, bulk rework, 402 responses)
- `app/models/concerns/account_email_rate_limitable.rb` (atomic capacity reservation)
- `lib/custom_exceptions/account.rb` (new `EmailLimitExceeded`), new `lib/custom_exceptions/inbox/limit_exceeded.rb`
- `app/models/inbox.rb` (before-create limit guard), `app/controllers/concerns/request_exception_handler.rb` (`rescue_from`), channel controllers (callbacks, Twilio, WhatsApp authorization)
- `app/helpers/api/v1/inboxes_helper.rb` (remove now-redundant controller-level check)
- Backend i18n `config/locales/en.yml` only (`super_admin.account_suspension.*`, `errors.account.email_limit_exceeded`)
- No database migration required: suspension history is stored in the existing `internal_attributes` jsonb column; limits already live in the existing `limits` jsonb column
