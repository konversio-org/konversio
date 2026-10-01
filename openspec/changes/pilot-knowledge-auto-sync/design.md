## Context

Konversio's Pilot knowledge layer already stores URL- and PDF-backed documents as `Pilot::Document` rows, derives searchable knowledge as `Pilot::AssistantResponse` rows rebuilt whenever document content changes, and runs an hourly `Pilot::Documents::SyncSchedulerJob` that re-enqueues eligible URL-backed documents through `Pilot::Documents::CrawlJob`. Caps exist (`Pilot::SyncLimits`: 50 per account, 1000 global per tick), as does a 2-hour stuck-`syncing` recovery window and a transient-fetch retry inside the crawl/ingestion path.

This change closes the remaining gap against the behavior upstream Chatwoot shipped for the same feature area in v4.14.0. **All upstream reference material lives in the Enterprise edition (`enterprise/` overlay, EE-licensed), so every item in this change is clean-room: the upstream code was read for behavioral understanding only, and this document and its specs re-express the requirements in original wording against Konversio's architecture.** No upstream class names, comments, error-string taxonomies, or copy are carried over. Everything lands in the core tree under the `Pilot::` namespace; no new tables are needed (the existing `pilot_documents` table and its `metadata` jsonb column absorb the new fields).

Konversio-specific constraints that shape the design:

- **Self-hosted only, no plans.** Upstream keyed refresh cadence off the billing plan. Konversio has no plan concept, so cadence becomes a per-account setting with an installation-wide default.
- **Existing crawl fan-out.** Konversio's initial ingestion crawls a seed URL into many child documents. Re-sync must not re-crawl; each document refreshes its own page only.
- **Sibling citation work.** Change `pilot-agent-sessions-and-citations` already specs server-side resolution of citation URLs with basic well-formedness checks. This change adds the network-level eligibility layer on top and deliberately does not re-spec that capability.

## Goals / Non-Goals

**Goals:**

- Re-sync only rebuilds derived knowledge when the source page actually changed (fingerprint comparison).
- Refresh cadence is configurable per account: daily (default), weekly, or monthly.
- Scheduled refreshes execute at randomized offsets so fleets of documents spread over a window instead of stampeding at the cron tick.
- Fetch failures are classified permanent (no retry, immediate failure state) or transient (bounded retries with backoff, then failure state), and the classification is stored for display.
- Operators can trigger a manual refresh of a single document and see sync state in the documents UI.
- Markdown files become a first-class, non-syncable knowledge source.
- Citation source URLs are only customer-visible when they pass network-level safety checks (public host, no credentials, well-formed `http(s)`).

**Non-Goals:**

- Changing the initial crawl/ingestion pipeline (`Pilot::Documents::CrawlJob` fan-out, PDF ingestion) beyond the failure-classification hand-off.
- Per-document (rather than per-account) cadence configuration.
- Sync analytics, drill-downs, or usage reporting for documents.
- Re-specifying citation rendering or index mapping (owned by `pilot-agent-sessions-and-citations`).
- Any change to the `Pilot::Assistant` model/table naming.

## Decisions

### Fingerprint comparison gates the content update, not the fetch

A refresh always fetches the page, then hashes the whitespace-normalized body and compares it to the stored fingerprint. Only a mismatch writes new `content` — which is what triggers the existing `Pilot::Document` callback that enqueues knowledge rebuilds — so unchanged pages cost one HTTP fetch and nothing else.

Alternatives considered:
- Compare HTTP caching headers (`ETag`/`Last-Modified`) instead of body hashes. Cheaper when supported, but unreliable across the arbitrary sites operators point Pilot at; a body hash works everywhere.
- Hash inside the scheduler before enqueueing. Would push fetch logic into the scheduler and break its single responsibility (eligibility + caps); the per-document job is the right place.

Rationale: one well-defined comparison point, no new callbacks, and the existing "content changed → rebuild knowledge" wiring stays the single rebuild trigger.

A document with no stored fingerprint (never refreshed under this change) records the fingerprint on its first refresh without emitting an "updated" outcome, so backfilled rows don't produce a wave of false change signals. A data migration baselines existing `available` web documents (mark synced, set last-synced from `updated_at`) so the new scheduler doesn't re-fetch the entire fleet on first deploy.

### Re-sync is a single-page refresh, separate from initial crawl

Scheduled and manual refreshes fetch only the document's own `external_link` via a new dedicated service + job (e.g. `Pilot::Documents::RefreshService` / `Pilot::Documents::RefreshJob`). The multi-page `CrawlJob` remains the initial-ingestion path only.

Alternatives considered:
- Keep re-using `CrawlJob` for refreshes (current behavior). A re-crawl re-walks the whole site per seed, multiplies Firecrawl spend, and rewrites child rows that didn't change — exactly the cost this change exists to remove.
- Refresh by re-crawling but diffing children. Much more machinery for marginal benefit; individual child documents are already single pages with their own rows and can be refreshed individually.

Rationale: every document row owns one page; refreshing that page is the minimal correct unit of work.

### Failure classification: permanent fails fast, transient retries on bounded backoff

The refresh pipeline classifies each failure from the fetch outcome: target gone, access refused, or empty retrieved body are **permanent** — the document is marked failed immediately and the job is not retried. Timeouts, connection/TLS failures, and upstream server errors are **transient** — the job retries a small fixed number of times on an increasing backoff (on the order of tens of seconds to a few minutes, matching the existing `CrawlJob` retry cadence) and only then marks the document failed. Anything unclassified is treated as an unexpected error: the document is marked failed with a generic category and the exception is reported once.

The stored failure category is a machine-readable code whose exact values are an implementation detail; the spec fixes only the permanent/transient semantics and that the category is recorded and exposed.

Alternatives considered:
- Retry everything on Sidekiq's default policy. Retrying a 404 for days wastes capacity and delays the operator-visible failure state.
- No retries at all. A brief outage of the customer's site would fail every document in the window.

Rationale: matches how operators think about the failures ("the page is gone" vs "the site is having a moment") and keeps Sidekiq's retry storm bounded.

### Cadence is a per-account setting with an installation default; jitter scales with cadence

Each account gets a sync frequency of daily (default), weekly, or monthly. The hourly scheduler tick remains, but eligibility is computed against the account's interval, and each due document is enqueued with a randomized delay drawn from a window sized to the cadence (up to a few hours for daily, up to about a day for weekly, up to a few days for monthly). The due window is deliberately widened (documents become eligible at half the interval) so a document whose jittered execution landed late does not skip its next window. Existing caps (50 per account per tick, 1000 global per tick) are unchanged and become configurable via installation config.

Alternatives considered:
- Keep the fixed 24-hour interval for everyone. Simple, but weekly/monthly is a real ask for large or slow-changing knowledge bases, and upstream validated the tiered cadences.
- Cron-per-cadence (three scheduler entries). Upstream did this because cadence was plan-derived; with a per-account setting a single hourly tick evaluating per-account intervals is simpler and keeps stuck-row recovery uniform.
- Exact-time scheduling per document (store `next_sync_at`). More precise, but adds a column and write traffic for no operator-visible benefit over jittered enqueueing.

Rationale: one scheduler, per-account control, load spread without a schema-heavy scheduler.

needs investigation: the exact storage and configuration surface for the per-account cadence (account settings jsonb vs a dedicated installation-config default plus account override) and whether the frequency selector lives in Pilot settings UI or super admin only.

### Markdown is a file-backed source: validated, immediately available, never synced, never cited

Markdown uploads (and pasted markdown) attach as a file, must be a `.md` file with a markdown/plain content type, are length-capped (an order of magnitude smaller than the 200k web-content cap; upstream used 10,000 characters), require non-empty content, and become `available` immediately without a crawl. Like PDFs, they receive a synthetic `external_link` so the per-assistant uniqueness constraint keeps working, are excluded from the re-sync eligibility scope, and are never eligible as customer-visible citation URLs (an uploaded file has no customer-resolvable link).

Alternatives considered:
- Store pasted markdown as a web-style document with content only. Breaks the `external_link` presence/uniqueness model and confuses the sync scope.
- Allow citation links to the installation's own attachment URL. Leaks the dashboard host to widget customers and creates an unauthenticated access question; out of scope here.

Rationale: file-backed sources already have an established pattern in this codebase (PDF); markdown follows it.

### Citation URL eligibility adds network-level checks on top of the sibling capability

A document's source URL is customer-visible only if all of the following hold: the document is web-backed (not an uploaded file); the link parses as `http` or `https` with a host and without userinfo; the host resolves via DNS; and every resolved IP address is publicly routable (rejecting private, loopback, link-local, and reserved ranges for both IPv4 and IPv6, including IPv6 translation prefixes that map back to local space). DNS resolution failure means ineligible. Links whose path ends in `.pdf` are excluded, matching the uploaded-PDF exclusion.

Alternatives considered:
- Reuse the existing SSRF-filtering request path at citation time. The fetch-time guard protects the server; the citation-time guard protects the customer-facing surface from links that were recorded before hardening or imported by other means. Both are needed; this decision is about the latter only.
- Validate at document save time only. DNS answers change; eligibility must be evaluated at citation resolution time.

Rationale: citations are rendered to end customers on behalf of the installation; a private-network or credential-bearing link must never reach that surface even if ingestion accepted the URL.

## Risks / Trade-offs

- **Fingerprint normalization too aggressive or too lax** → Normalize only whitespace runs and trim; do not lowercase or strip markup, or trivially different pages collide / cosmetically re-rendered pages rebuild.
- **Jitter delays urgent refreshes** → Manual "refresh now" bypasses jitter and executes promptly; scheduled freshness is a background concern.
- **Cadence setting drift from scheduler expectations** → The documents index API must expose the account's effective interval so the UI's stale/up-to-date filters agree with the scheduler.
- **DNS lookups at citation resolution time add latency** → Resolution happens once per reply assembly over a small set of cited documents; acceptable, but flagged for the implementer to time-box with a resolver timeout.
- **Markdown length cap surprise** → 10k characters is much smaller than the web cap; the UI must validate client-side and show the limit.

## Migration Plan

1. Add the composite index on `pilot_documents (account_id, assistant_id, sync_status, last_synced_at)` and the backfill migration baselining existing `available` web documents as synced (last-synced from `updated_at`). No data is deleted.
2. Ship the refresh service/job, failure taxonomy, and scheduler changes behind the existing Pilot feature flags; manual refresh and markdown upload are additive API surface.
3. Rollback: stop the scheduler entry and revert; baselined sync columns are harmless, markdown documents remain readable as ordinary file-backed rows.

## Open Questions

- Where does the cadence selector live (Pilot settings UI vs super admin) and where is it stored? See `needs investigation` note under Decisions.
- Should an unchanged refresh still emit the `pilot.autopilot.document.crawled`-style domain event? Current leaning: emit a distinct refresh-completed outcome only on actual content change, and log unchanged/skipped outcomes for observability without dispatching consumer events.
- Do markdown documents count against the same per-account document usage limit as web/PDF documents? Leaning yes (same quota pool), to be confirmed against `Account#update_document_usage` behavior at implementation time.
