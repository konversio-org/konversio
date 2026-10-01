## Context

Konversio forked Chatwoot at v4.13.0. The Super Admin (Administrate) account dashboard already exposes a `status` select (Active/Suspended) and a free-form `limits` jsonb field, and the fork already taught `Account#usage_limits` (`app/models/account.rb:157`) to honor per-account `limits['agents']` / `limits['inboxes']` overrides — that part of the upstream EE `get_limits` behavior is already re-expressed in core, so this change does not need to touch it.

What is missing relative to upstream v4.16.1/v4.16.2:

1. **Suspension metadata** (upstream v4.16.2, core/MIT): suspension category + reason, validated on update, persisted as events in `internal_attributes['suspensions']`, with two new Administrate fields and a small JS toggle in the superadmin entrypoint.
2. **Agent quota race** (upstream v4.16.1, core/MIT): `Api::V1::Accounts::AgentsController` checks the limit before calling `AgentBuilder`, with no lock. Upstream moved the check inside `AgentBuilder#perform` under `account.with_lock`, raising `AgentBuilder::LimitExceededError`.
3. **Agent invitation email limit** (upstream v4.16.2, core/MIT): invitation confirmation emails now reserve daily email capacity via `AccountEmailRateLimitable#reserve_email_send_capacity` (Redis WATCH/MULTI) before commit, and are sent explicitly after the transaction instead of via the Devise create callback.
4. **Inbox limit coverage** (upstream v4.16.2 "account limits" hardening): upstream raises `CustomExceptions::Inbox::LimitExceeded` (core/MIT exception class) from a `before_create` guard and rescues it in the channel controllers and `RequestExceptionHandler` (all core/MIT). The one-line guard itself ships in upstream's `enterprise/` overlay; its *behavior* (reject inbox creation once the account limit is reached) is re-expressed here in Konversio's core `Inbox` model — there is nothing beyond that single comparison to port.

**License note:** Items 1–3 and the exception/rescue plumbing of item 4 are verbatim-portable MIT code from upstream's core tree; the tasks below reference upstream v4.18.0 files directly. The only EE-adjacent piece is the model-level inbox guard placement, specified here at the requirements level (original wording) since Konversio has no `enterprise/` directory and the guard must live in the core `Inbox` model.

## Goals / Non-Goals

**Goals:**

- Require and record a category and reason whenever a super admin suspends an account; keep an append-only history of suspension events.
- Make the agent quota check race-safe for both single and bulk invitation paths.
- Count invitation emails against the account's daily outbound email limit without sending mail from inside the transaction.
- Enforce the inbox limit on every inbox creation path, not just `inboxes#create`.
- Return consistent, machine-readable error responses (402 for quota/limit failures, 429 for daily email limit).

**Non-Goals:**

- Surfacing suspension metadata to the suspended account's users or changing the suspended-account banner/flow.
- Billing, plans, or self-service limit upgrades (Konversio is self-hosted only; limits are set by the super admin).
- Per-account email-rate-limit configuration beyond the existing `limits['emails']` override already understood by `AccountEmailRateLimitable`.
- Changing `usage_limits` resolution (already honors the `limits` column in the fork).
- Captain/Pilot model overrides (`captain_models`) shown in the same upstream dashboard diff — out of scope, tracked separately.

## Decisions

### Store suspension history in `internal_attributes['suspensions']`

Each suspension event is a hash of `category`, `reason`, `suspended_at` (ISO 8601) appended to a list in the existing `internal_attributes` jsonb column. This matches upstream v4.18.0 exactly (`Account#suspension_history`).

Alternatives considered:
- A dedicated `account_suspensions` table. Cleaner relationally, but adds a migration, a model, and Administrate wiring for data that is written rarely and read only by super admins.
- Overwriting a single `suspension_reason` column. Loses history on re-suspension, which is precisely the audit trail this feature exists to provide.

Rationale: zero-migration, faithful to the upstream MIT implementation, and the volume of events per account is tiny.

### Validate suspension metadata in the controller, not the model

`SuperAdmin::AccountsController` validates category/reason in a `before_action` on `update` and re-renders the edit form with 422 on failure. The model only carries `SUSPENSION_CATEGORIES`, two virtual attributes, and the history reader.

Alternatives considered:
- Model validations on `Account`. The metadata is required only when the *super admin form* transitions status to suspended; API/platform updates of `status` must not suddenly start failing on accounts without metadata.

Rationale: keeps the requirement scoped to the Super Admin workflow; matches upstream.

### History update semantics

- Suspending an **active** account appends a new event.
- Saving an **already suspended** account with changed metadata updates the latest event in place (no new timestamp).
- A legacy account suspended before this feature (status `suspended`, empty history) gets one event appended only if metadata was actually provided; otherwise the save succeeds without metadata (grace period for legacy data).

Rationale: mirrors upstream `suspension_history_with_changes` behavior and avoids fabricating history entries with empty categories.

### Move the agent quota check into `AgentBuilder` under a row lock

`AgentBuilder#perform` wraps the limit check and the user/account-user creation in `account.with_lock`, raising `AgentBuilder::LimitExceededError` when `account_users.count` has reached `usage_limits[:agents]`. The controller rescues and renders 402. Bulk create takes the same lock once, pre-checks `emails.count` against the remaining capacity, then creates each agent inside it.

Alternatives considered:
- Keep controller `before_action` checks and add locking there. Leaves the builder unsafe for any other caller (e.g. onboarding, seeds, future API paths).
- A unique constraint or counter cache. Overkill; the row lock on the account serializes invitations, which are low-frequency.

Rationale: the check and the write are atomic per account regardless of entry point. This is the upstream v4.16.1/v4.16.2 approach, verbatim-portable MIT code.

### Count members, not users

The remaining-capacity calculation uses `account.account_users.count` (seats consumed), not the ordered/eager-loaded `users` relation the old controller used.

Rationale: `account_users` is the seat-granting record; it is both more accurate and cheaper. Matches upstream.

### Reserve invitation email capacity before commit, send after commit

For a *newly created* user, `AgentBuilder` calls `skip_confirmation_notification!`, reserves one unit of daily email capacity inside the transaction via `reserve_email_send_capacity`, and sends confirmation instructions after the lock/transaction completes. If capacity is exhausted it raises `CustomExceptions::Account::EmailLimitExceeded`, rolling back the user creation — no orphan uninvited users. Re-inviting an existing unconfirmed user does not reserve or resend.

`reserve_email_send_capacity` uses Redis WATCH/MULTI so concurrent invitations cannot overshoot the daily counter.

Alternatives considered:
- Let Devise send the confirmation on create (current behavior). The mail fires inside the transaction (lost on rollback) and bypasses the daily email limit entirely.
- Check-then-increment without WATCH. Racy under concurrent bulk invitations.

Rationale: verbatim-portable MIT upstream code; fixes both the limit bypass and the send-inside-transaction bug.

**Cloud-gate caveat:** upstream gates `reserve_email_send_capacity` behind `KonversioApp.chatwoot_cloud?` (always false on self-hosted Konversio), so the reservation is a no-op outside a cloud deployment env. This change keeps that gate to stay faithful to upstream. needs investigation: whether Konversio wants the daily outbound email limit to be enforceable on self-hosted installs (would require a Konversio-specific gate decision, e.g. an env flag).

### Enforce the inbox limit in the `Inbox` model, raise a core exception

Add a `before_create` guard on `Inbox` that raises `CustomExceptions::Inbox::LimitExceeded` (new core exception, ported verbatim from upstream MIT `lib/custom_exceptions/inbox/limit_exceeded.rb`, HTTP 402) when the account already has `usage_limits[:inboxes]` inboxes. Remove the controller-level `validate_limit` from `Api::V1::InboxesHelper`. Channel-specific controllers that create inboxes inside broad `rescue StandardError` blocks (Facebook/Instagram callbacks, Twilio, WhatsApp embedded signup) rescue the new exception explicitly *first* and render the 402 instead of a generic creation error. `RequestExceptionHandler` gains a `rescue_from` for both limit exceptions as a backstop.

Alternatives considered:
- Keep adding `validate_limit` before-actions to every controller path. This is the status quo that upstream's hardening fixed — any new channel flow can forget the check.
- Validate via a model validation (add to `errors`) instead of raising. A validation failure surfaces as 422 record-invalid, not the 402 the dashboard/API clients already handle for limits; upstream standardized on the exception.

Rationale: one guard covers all present and future creation paths. The exception class and rescue wiring are upstream MIT; the guard's behavior is re-expressed in core because Konversio has no `enterprise/` overlay (see license note above).

## Risks / Trade-offs

- **Legacy suspended accounts** (suspended before this change) have no history -> the form treats metadata as optional for them until any is entered; no backfill is attempted.
- **Row lock contention** on `accounts` during bulk invitation -> invitations are rare and fast; the lock window is a few INSERTs.
- **Inbox guard query cost** (`inboxes.count` per create) -> negligible; inbox creation is rare.
- **`prepend_mod_with` cleanup** -> the fork still carries dangling `prepend_mod_with` calls in `agents_controller.rb` and `agent_builder.rb`; they are no-ops without the enterprise overlay. Remove them in the touched files per repo guidance (no `prepend_mod_with` dance).

## Migration Plan

1. Deploy code only — no migrations. `internal_attributes` and `limits` jsonb columns already exist.
2. Rollback by reverting; suspension events already written to `internal_attributes` are inert data that older code ignores.

## Open Questions

- Should the daily outbound email limit (and invitation reservation) be made enforceable on self-hosted installs instead of staying behind `KonversioApp.chatwoot_cloud?`? Default: keep the upstream gate. needs investigation: product decision required.
- needs investigation: the changelog maps "agent quotas" to v4.16.1 and "agent invitation limit" / "account limits" to v4.16.2, but the shallow upstream clone only carries squashed release-merge history, so the exact PR split between the two releases cannot be confirmed; the specs below describe the end state at v4.18.0.
