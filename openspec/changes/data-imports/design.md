## Context

Konversio's fork base (Chatwoot v4.13.0) ships a minimal `DataImport` model: a contacts CSV upload processed asynchronously by `DataImportJob`, with only `total_records` / `processed_records` / `processing_errors` bookkeeping. There is no way to import conversations or to pull data from another helpdesk's API.

Upstream built the replacement in three steps, all in the MIT-licensed core tree (no `enterprise/` involvement), which means **every item in this change is an MIT port**: upstream files may be referenced directly and ported verbatim where they fit. The upstream references are:

- v4.16.0 — Intercom import workflow: `DataImports::Intercom::*` (client, credentials validator, source, importer, message batch builder, activity content builder, placeholder inbox builder), the `DataImports::Importer` engine, the page-job chain, `data_import_items` / `data_import_mappings` / `data_import_errors` tables, the REST controller, and the Settings → Data UI.
- v4.16.2 — retry and reliability: `DataImports::RestartService`, `DataImports::RetryService`, stall detection (`IMPORT_STALLED_AFTER = 15.minutes`), active-run-id fencing, `retry_on` / rate-limit handling in the job base classes, and the skip-log/error-log model and CSV exports.
- v4.17.0 — Freshdesk import: `DataImports::Freshdesk::*` (client, normalizer, ticket page, source bucket, metadata, credentials validator), plus the generalization of the framework from Intercom-only to a provider registry (`DataImports::Source`) — including renaming Intercom-specific model hooks to provider-neutral ones while keeping backward-compatible aliases.

Reference implementation for all of the above is visible with `git -C /tmp/chatwoot-upstream diff v4.13.0 v4.18.0 -- app/services/data_imports app/jobs/data_imports app/models/data_import*`.

Because the port lands wholesale, this design doc records the upstream architectural decisions Konversio inherits, with the alternatives upstream weighed, rather than re-deriving them.

## Goals / Non-Goals

**Goals:**

- Import contacts and conversations from Intercom, and contacts, tickets, replies, and private notes from Freshdesk, via each platform's REST API.
- Make imports resumable, idempotent, and observable: persisted cursors, per-record outcomes, error/skip logs, progress stats, CSV log export.
- Let admins start, monitor, retry a stalled import, restart a failed/abandoned import, and abandon an active import from the dashboard.
- Keep the legacy contacts CSV import working exactly as before.
- Land everything in the core tree (`app/`, `lib/`, `db/`) — Konversio has no `enterprise/` split to preserve.

**Non-Goals:**

- Importing from any other source platform (the provider registry makes this possible later, but no third provider is in scope).
- Mapping imported conversations into existing live inboxes, or importing channel-specific objects (WhatsApp threads, email channel wiring). Imported data lands in placeholder API inboxes.
- Importing attachments (attachment payloads are noted in logs and replaced with a text placeholder).
- Two-way sync or incremental re-import of new data after the initial run (re-running an import only reconciles records already mapped).
- Migrating agent/admin identities from the source platform (imported messages are attributed to contacts or left unattributed; no `User` records are created).

## Decisions

### Port the upstream MIT implementation directly

All three changelog items are core-tree MIT code. Verbatim porting is legal and is the lowest-risk path: the importer contains subtle concurrency, idempotency, and stats-reconciliation logic that would be expensive to re-derive and re-validate. Deviations should be limited to Konversio integration points (feature flag registration, branding, i18n file locations).

Alternatives considered:
- Clean-room reimplementation. Only warranted for EE code; here it would add risk with no licensing benefit.
- Cherry-picking upstream commits. Not viable — Konversio has no upstream tracking, and the fork renamed Captain → Pilot; a manual port with conflicts resolved is the practical route.

Rationale: license permits it, and the upstream code has production mileage including the v4.16.2 reliability hardening.

### One provider-agnostic importer engine with per-provider source adapters

A single `DataImports::Importer` drives the whole lifecycle; each provider supplies a `Source` adapter that normalizes its API into a shared payload shape (contacts list, conversation summaries, conversation detail with `source` + `conversation_parts`). Freshdesk's `Normalizer` reshapes tickets/replies/notes into the same shape Intercom returns, so the engine never branches on provider.

Alternatives considered:
- A separate importer per provider. Duplicates the pagination, mapping, stats, and message-write logic; upstream deliberately consolidated after building Freshdesk.

Rationale: the shared engine is where the reliability logic lives; adapters stay thin and testable.

### Page-at-a-time background job chain with persisted cursor

Imports run as a chain of `DataImports::*PageJob` jobs (one API page per job, self-enqueueing) on the `:low` queue, persisting `cursor.contacts` / `cursor.conversations` (with `starting_after`, `completed`, `updated_at`) after each page. The contacts stage completes before conversations start. A heartbeat (`touch` every minute) feeds stall detection.

Alternatives considered:
- One long-running job for the whole import. Cannot survive deploys/restarts and gives no resume point; upstream's original v4.16.0 shape, replaced by the page chain.

Rationale: resumability and Sidekiq-friendly short jobs; a crashed worker loses at most one page.

### Idempotency via mappings, identifiers, and per-item rows

- `data_import_mappings` enforces one mapping per `(account, provider, object type, source id)` with a unique index; message mappings are upserted on that index.
- Contacts are matched to existing contacts by `identifier` (external id), then email (case-insensitive), then E.164 phone; matched contacts are enriched (name/email/phone/identifier filled only when blank) rather than duplicated.
- Conversations get `identifier = "<provider>:<source id>"` and messages get `source_id = "<provider>:<source id>"`, so re-runs find and skip existing records.
- `data_import_items` tracks each source object's status (`pending/processing/imported/skipped/failed`), attempt count, and last error; items already `imported`/`skipped` are not redone, and a Postgres advisory lock per item serializes concurrent handling.

Alternatives considered:
- Always creating new records. Produces duplicates on retry and on re-import.
- Deduping only by content. Fragile across providers and locales.

Rationale: retries (page level, job level, whole-import level) must be safe to run repeatedly.

### Stale-run fencing with an active run id

Every start/restart/retry assigns a fresh `active_import_run_id` (stored in `source_metadata`). Each job carries its run id and no-ops when the import's active run id has moved on, so orphaned jobs from a previous run cannot write into a restarted import.

Alternatives considered:
- Status checks alone. A restarted import is `pending`/`processing` again, so old jobs would pass status checks and double-write.

Rationale: run-id fencing makes job-level retries and manual restarts safe at once.

### Stall detection and operator-driven retry instead of silent auto-resume

An integration import untouched for 15 minutes while `pending`/`processing` is `stalled?`. The UI surfaces this and offers **Retry** (`DataImports::RetryService`), which re-enqueues from the persisted cursor after checking no other integration import is active. Failed/abandoned imports offer **Restart** (`DataImports::RestartService`), which resets the run (retaining skip logs so previously skipped records stay skipped) and starts over. Active imports can be **abandoned** (`abandon!` with a row lock), which all in-flight jobs honor at their next checkpoint. Only one active integration import per account is allowed, enforced under an account lock.

Alternatives considered:
- Automatic re-enqueue of stalled imports. Risks thundering re-runs against a rate-limited source API and hides systemic failures.
- Deleting and recreating the import record. Loses mappings, skip logs, and stats history.

Rationale: imports are rare, operator-supervised events; explicit actions keep failure modes visible.

### Placeholder API inboxes bucketed by source type

Imported conversations are routed to auto-created `Channel::Api` inboxes named `"<Provider> Import - <Bucket>"` (e.g. "Intercom Import - Email", "Freshdesk Import - Chat"). The channel's `additional_attributes` mark it as an import placeholder (`source_provider`, `source_bucket`, `import_placeholder: true`, `agent_reply_time_window: 1`), auto-assignment and replies-after-resolve are disabled, and default working hours are created. Buckets group the provider's many source types into a small set of inboxes.

Alternatives considered:
- A single "Imported" inbox per provider. Loses the source-channel distinction users expect when reviewing history.
- Letting the admin pick real inboxes. Wrong semantics — these are historical, resolved records, not live threads.

Rationale: reviewable grouping without pretending imported history is live.

### Bulk writes with per-record fallback and no callbacks

Contacts, conversations, and messages are written with `insert_all!` in batches (messages in batches of 100), skipping validations/callbacks — so no notifications, no auto-assignment, no round-robin. Messages are reindexed for search explicitly where indexing applies. On `ActiveRecord::QueryCanceled` the batch retries once after a short jittered sleep; on other DB errors the batch falls back to per-message inserts so one bad record fails alone and is logged. Imported conversations are created as `resolved` with the source timestamps preserved (`created_at`, `updated_at`, `last_activity_at`); message sender attribution resolves through contact mappings, and author types map to incoming/outgoing, with source-platform notes becoming private messages.

Alternatives considered:
- Row-by-row `create!`. Triggers callbacks/notifications and is far slower for large histories.
- Skipping the per-record fallback. One malformed record would fail an entire batch and its siblings.

Rationale: bulk speed plus contained failure blast radius; search indexing is the one callback-equivalent kept.

### Freshdesk ticket-list pagination cap

Freshdesk's ticket list API stops paginating after 300 pages; the client detects this and raises `CustomExceptions::DataImport::FreshdeskTicketLimitError`, which the job discards gracefully (the import completes with what it has, and the limit is surfaced rather than crashing the worker).

Alternatives considered:
- Switching to Freshdesk's search/export APIs. Out of scope for the port; needs investigation if a Konversio customer hits the cap.

Rationale: matches upstream behavior; the cap only affects very large Freshdesk accounts (~30k+ tickets at default page size).

### Feature flag and permissions

The endpoints and UI sit behind a new `data_import` account feature flag and an administrator-only `DataImportPolicy`. needs investigation: upstream places the flag in a `feature_flags_ext_1` bitset column introduced after the fork base; Konversio's `config/features.yml` has no extension columns, so the implementer must decide where the flag's bit lives (append to `feature_flags` if a slot is free, or port the extension-column mechanism).

## Risks / Trade-offs

- **Large port surface** -> Mitigate by porting file-by-file with upstream specs (`spec/` counterparts exist upstream for the importer, services, jobs, controller, and Vue components) and running them against the Konversio tree.
- **Skip-heavy logic drift** -> The v4.16.2 skip-log/stat-reconciliation code is intricate; do not "simplify" during the port — port it as-is first.
- **`import_placeholder` inboxes visible in the UI** -> Acceptable upstream behavior; hidden-channel filtering can be a follow-up if users complain.
- **Source API changes** -> Intercom client pins API version 2.15; Freshdesk client uses the v2 REST API. Pin and document both.
- **Access token storage** -> Encrypted via `encrypts :access_token` when `Chatwoot.encryption_configured?` (Konversio: `Konversio.encryption_configured?` if rebranded — check `lib/chatwoot_app.rb` equivalent); deployments without encryption configured store it in plaintext, same as upstream.

## Open Questions

- Where the `data_import` flag's bit lives in Konversio's features.yml (see Decisions).
- Whether Konversio wants the import UI strings to reference the source platforms by name (upstream copy does: "Intercom import", "Freshdesk import") — assumed yes, as these are third-party product names, not Chatwoot branding.
- Whether the Freshdesk 300-page ticket cap needs a follow-up path (needs investigation: upstream offers none).
