## Why

Konversio's fork removed the `enterprise/` overlay, which carried the entire audit log subsystem: event recording, the admin API, and the privacy controls. What remains in the core tree is the `audits` table, the `audited` gem (its custom audit class configuration is commented out in `config/initializers/audited.rb`), a read-only settings page shell that calls a backend endpoint with no controller behind it, and an `audit_logs` feature flag. Administrators currently have no way to review who did what in an account.

Upstream v4.17.0 added filtering, actor search, and sorting to audit logs; v4.18.0 added message deletion audit entries, default IP masking, and geolocation details. This change rebuilds the subsystem in Konversio's core tree (there is no enterprise split) at that functional level, as a clean-room re-specification of the enterprise-licensed reference material.

## What Changes

- Re-enable the `audited` gem with a new core `AuditLog` model and record account-scoped audit entries for: sign-in/sign-out, agent and team administration, inbox/team membership changes, account and channel configuration (inboxes, webhooks, automation rules, macros), and conversation deletion.
- Record an audit entry whenever a message is deleted, capturing a server-side snapshot of the deletion context (owning conversation, inbox, sender, original body) while never serving the body back through the API.
- Add an admin-only audit log API behind the existing `GET /api/v1/accounts/:account_id/audit_logs` route with event-type filtering, actor search (name or email), a date window, newest/oldest sort, and 25-per-page pagination.
- Rebuild the audit logs settings page: debounced actor search, grouped event-type filter, date-range picker, sort control, clear-filters action, result count, and URL-synced filter state. Make the route available to self-hosted installations.
- Mask recorded IP addresses by default (network portion only); return full addresses only when a new per-account flag is enabled.
- Optionally resolve city/country for recorded addresses using the existing core IP lookup infrastructure, via asynchronous jobs (per entry, batched for sign-in events) plus a cursor-based backfill job and rake task.

## Capabilities

### New Capabilities
- `audit-event-recording`: Account-scoped recording of security- and governance-relevant events, including sign-in/sign-out entries and message deletion snapshots, with actor identity denormalized at write time.
- `audit-log-browsing`: Admin-only API and settings UI for listing audit entries with event-type filters, actor search, date window, sort order, and paginated, URL-synced results.
- `audit-log-ip-privacy`: Default masking of recorded IP addresses, an opt-in full-address flag, and asynchronous geolocation resolution with backfill for location display.

### Modified Capabilities
None.

## Impact

- `audits` table: new `city`, `country`, `country_code` columns; new composite index on `(associated_type, associated_id, created_at)` added concurrently.
- `config/initializers/audited.rb`: audit class re-enabled; new core model `app/models/audit_log.rb`.
- Models gaining audit declarations: `Account`, `AccountUser`, `Inbox`, `Webhook`, `AutomationRule`, `Macro`, `Team`, team/inbox membership records, `Conversation` (deletion only).
- `DeviseOverrides::SessionsController`: sign-in/sign-out entries.
- `Api::V1::Accounts::Conversations::MessagesController#destroy`: deletion audit entry under a row lock.
- New `Api::V1::Accounts::AuditLogsController` + jbuilder view backing the existing route in `config/routes.rb:98`.
- New jobs (`app/jobs/audit_log_*`) and `lib/tasks/audit_log.rake`; reuses core `IpLookupService` and the `ip_lookup:setup` GeoIP database provisioning.
- `config/features.yml`: new `audit_log_ip_address` flag (jsonb feature storage — no bitmask column needed); `app/helpers/super_admin/features.yml` entry.
- Frontend: audit logs settings page, filters component, store module, API client, helper, route meta; English i18n only (`en.json`).
- Swagger audit log definitions and paths.
