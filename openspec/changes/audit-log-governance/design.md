## Context

The `audits` table and the `audited` gem survive from the Chatwoot core tree, but every behavioral piece of audit logging lived in the removed `enterprise/` overlay: the audit model subclass, per-model `audited` declarations, the sessions hook that wrote sign-in/sign-out entries, the admin controller and view, and the IP privacy layer. `config/initializers/audited.rb` in Konversio today carries a commented-out `config.audit_class` line noting the dangling reference.

The upstream reference for this change is enterprise-licensed (EE), so **all backend behavior is specified clean-room**: the upstream code informed our understanding of workflows, data shapes, and edge cases, but every requirement here is expressed in original wording and targets Konversio's core tree. The frontend plumbing that upstream changed (API client, store module, route shell, settings page) lives in upstream's **MIT-licensed core tree**, so direct porting of that layer is legal; we still re-express it as requirements here and write our own i18n copy.

Konversio-specific architectural facts that shape the design:

- Feature flags live in `accounts.feature_flags` (jsonb) via `Featurable`, which auto-generates `feature_<name>` scopes and accessors from `config/features.yml`. Upstream put its new flag in a second bitmask column; Konversio needs no column for this.
- `IpLookupService` and `Geocoder::SetupService` (MaxMind GeoIP2 database provisioned from `IP_LOOKUP_API_KEY` via `rake ip_lookup:setup`) already exist in core and are reused as-is.
- There is no `enterprise/` overlay and no `prepend_mod_with` dance — recording hooks go directly into core models and controllers.

## Goals / Non-Goals

**Goals:**

- Record governance-relevant events account-scoped, with actor identity and request IP captured at write time.
- Record message deletions with a server-side snapshot sufficient to identify the affected conversation and sender, while guaranteeing the deleted body is never exposed through the audit API.
- Provide an admin-only browsing API and UI with event-type filtering, actor search, date window, sort, and pagination.
- Mask IPs by default; full addresses only behind an explicit per-account opt-in.
- Resolve and display coarse location (city, country) when the account has IP lookup enabled, without ever blocking the audited action on geolocation.
- Keep all of it in the core tree under 100% MIT.

**Non-Goals:**

- Audit log export, retention/pruning policies, or tamper-evidence (hash chaining) — possible follow-ups.
- Super-admin cross-account audit views.
- Auditing arbitrary models beyond the governance set defined here.
- Real-time push of audit entries to the UI.
- Auditing Pilot AI internals (Pilot actions surface through the same user/message records they already write; no Pilot-specific audit categories in this change).

## Decisions

### One core `AuditLog` model subclassing `Audited::Audit`, reusing the existing `audits` table

Create `app/models/audit_log.rb` (`AuditLog < Audited::Audit`), re-enable `config.audit_class` in `config/initializers/audited.rb`, and extend the existing `audits` table with `city`, `country`, `country_code` string columns plus a concurrently-built composite index on `(associated_type, associated_id, created_at)`.

Alternatives considered:
- A new `pilot_`-prefixed table. The `audits` table is core MIT schema already present in every Konversio database; a parallel table would duplicate the audited gem's machinery for no licensing benefit. The `pilot_` prefix rule applies to new tables, and this is not one.
- Auditing via hand-rolled callbacks only, without the gem. The gem already provides the change-tracking, versioning, and request store; re-implementing invites drift.

Rationale: minimal new schema, maximal reuse of battle-tested core plumbing.

### Denormalize actor identity at write time

Every entry persists the acting user's email (and the account association) at write time, so entries stay meaningful after a user is deleted or renamed. Account-level actions (e.g. account settings changes) are also stamped with the account as the entry's association so account-scoped listing never scans other accounts' rows.

Rationale: audit trails outlive the users they describe; joins at read time would lose deleted actors.

### Message deletion: snapshot under a row lock, redact at serialization

Message deletion in Konversio is a soft delete (body replaced with a deleted-placeholder, attachments removed). The audit entry is created inside the same row lock that performs the soft delete, after the delete, and skipped if the message is already marked deleted — so concurrent deletes cannot produce duplicate entries. The snapshot stored in the entry's change payload identifies the conversation (id and human-facing display number), inbox, sender type/id, and the original body. Serialization strips the body and serves no message payload for message entries.

Alternatives considered:
- Omit the body from the stored snapshot entirely. We keep it server-side because a deletion audit that cannot establish *what* was removed has limited forensic value; the guarantee that matters is that the API never returns it, which is enforced at serialization with a test.
- Audit via an `audited` model declaration on `Message`. The soft-delete flow is controller-driven and needs the lock + already-deleted guard; a model-level declaration would also fire on hard deletes from unrelated paths (e.g. conversation cascade), producing noisy entries.

Rationale: exactly one entry per deletion, no content leakage, no cascade noise.

### Mask IPs by default; full addresses behind a new account flag

`remote_address` continues to be stored in full (needed for later geo resolution and forensics), but API responses mask it unless the account enables a new `audit_log_ip_address` flag. Masking keeps the network portion and blanks the host portion: IPv4 keeps the first three octets and replaces the last with a placeholder (`203.0.113.7` → `203.0.113.x`); IPv6 keeps the first four hextets and truncates the rest (`2001:db8:85a3:8d3:…` → `2001:db8:85a3:8d3::`); blank or unparseable values serialize as null.

Alternatives considered:
- Mask at write time. Destroys forensic and geo value permanently; a flag flip could never recover it.
- Reuse the existing `ip_lookup` flag to also mean "show full IPs". Conflates two unrelated decisions (geo enrichment vs. address disclosure).

Rationale: privacy-safe default with a deliberate, per-account opt-out; storage stays complete.

### Geolocation is always asynchronous, on the low queue, and never blocks the audited action

Three entry points, all reusing the core `IpLookupService` (no-op when the GeoIP database is absent):

1. **Per entry** — after create-commit, when the entry has a remote address and its account has `ip_lookup` enabled, enqueue a low-priority job that resolves and writes `city`/`country`/`country_code` with `update_columns`; failures are logged and swallowed.
2. **Batched for sign-in/out** — all entries of one sign-in event share one address, so the sessions flow enqueues a single job that resolves once and bulk-updates the batch, gated on at least one involved account having `ip_lookup` enabled. Enqueueing is wrapped so a job-backend failure can never interrupt authentication.
3. **Backfill** — a cursor-based job walks existing rows that have an address but missing geo fields (accounts with `ip_lookup` only), in batches of 500 with a short delay between self-reschedules; triggered by a rake task. Per-row failures are logged and skipped.

Alternatives considered:
- Synchronous lookup at record time. Adds a geolocation dependency (and its failure modes) to sign-in and message deletion — unacceptable.
- A periodic cron sweep instead of self-rescheduling batches. Self-rescheduling with a cursor is simpler to reason about and naturally stops when caught up.

Rationale: location is best-effort enrichment; the audited action must never wait on or fail because of it.

### Read API: tolerant parameter validation, fixed page size, single sort dimension

The listing endpoint accepts `page`, `q`, `types[]`, `since`/`until` (unix epoch seconds), and `sort` (`asc`|`desc`, default `desc`). Epoch values are validated against the database-representable range (0 through year 9999); invalid or out-of-range values are ignored rather than rejected with 400. Page size is fixed at 25. Actor search matches the denormalized username or the linked user's name/email as a case-insensitive substring with LIKE metacharacters escaped, joining users only for entries whose actor type is `User`. Results order by `created_at` only.

Alternatives considered:
- Strict 400s on malformed filters. These parameters arrive from a URL query bar; silently ignoring junk matches how the rest of the settings UI behaves and keeps shared/bookmarked URLs robust.
- Multi-column sort. Not needed for a chronological trail.

Rationale: a chronological admin trail values predictability over flexibility.

### Route and flag availability in self-hosted Konversio

The settings route currently gates on cloud/enterprise installation types; it must include self-hosted. The `audit_logs` flag stays the on/off gate for the whole feature. needs investigation: the `audit_logs` flag is marked `premium: true` in `config/features.yml` — determine whether premium gating is still meaningful in self-hosted-only Konversio, or whether the flag should default on / drop the premium marker.

## Risks / Trade-offs

- **Recording breadth vs. noise** — the governed model set is deliberately narrow; widening it later is additive and safe, narrowing after launch strands existing entries.
- **`audited` callbacks on hot models** — declarations are restricted to low-frequency admin actions (membership, configuration) plus conversation/message deletion; message create/update is explicitly not audited.
- **Index build time** — the composite index uses `algorithm: :concurrently` with `disable_ddl_transaction!` so large existing `audits` tables are not locked.
- **Geo data accuracy** — GeoIP city data is coarse and depends on the operator provisioning the database; the UI must treat location as best-effort and fall back to the (masked) IP.

## Open Questions

- Should sign-in/sign-out entries be recorded for super admins as well, or only account users? Current assumption: account users only (super admin has its own separate auth surface).
- Does the backfill need a progress-reporting mechanism beyond logs for very large existing tables? Current assumption: logs suffice for a one-shot operator task.
