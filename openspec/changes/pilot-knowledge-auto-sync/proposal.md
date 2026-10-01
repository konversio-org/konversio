## Why

Pilot knowledge documents backed by external URLs go stale as the underlying pages change, but today's re-sync support is blunt: the hourly `Pilot::Documents::SyncSchedulerJob` re-runs the full ingestion path for every eligible document on a fixed 24-hour interval, rebuilds derived knowledge (`Pilot::AssistantResponse` rows and embeddings) even when nothing changed, treats every fetch failure alike, and gives operators no cadence control. On large installations this wastes crawl quota, embedding spend, and Sidekiq capacity, and it can surface spurious "updated" signals for pages that merely re-fetched.

Upstream Chatwoot v4.14.0 (Enterprise edition) shipped a "document sync" feature covering exactly this gap: content-change detection before rebuilding knowledge, configurable refresh cadences with spread-out execution, a permanent-vs-transient failure classification, markdown files as a knowledge source type, and safety checks on the source URLs Pilot shows to customers as citations. Konversio should carry the same behavior into the MIT `Pilot::` layer.

Additionally, citation URLs currently shown to customers are only checked for basic well-formedness (see `pilot-response-citations`). A self-hosted instance crawling arbitrary operator-supplied URLs needs network-level validation so a document whose host resolves to a private, loopback, or otherwise non-public address is never presented as a customer-facing source link.

## What Changes

- Add **fingerprint-based change detection** to URL-backed document refresh: after fetching a page, compare a hash of the normalized content against the stored fingerprint; skip the content update and the downstream knowledge rebuild when nothing changed.
- Split **re-sync** from **initial crawl**: scheduled and manual refreshes fetch the document's own page only; the multi-page crawl fan-out stays reserved for first ingestion.
- Introduce a **permanent vs transient failure taxonomy** for fetches: permanent failures (page gone, access refused, empty body) fail immediately without retry; transient failures (timeouts, connection errors, server errors) retry on a bounded backoff before marking the document failed. The last failure category is recorded on the document for display.
- Make refresh cadence **configurable per account** (daily, weekly, or monthly; daily default) with a **randomized per-document delay** so large fleets of documents do not all fetch at the same moment, while keeping the existing per-account and global enqueue caps.
- Add a **manual "refresh now"** endpoint and surface sync state (status, last attempt, last success, last failure category, current phase) in the documents API and Pilot documents UI.
- Support **markdown files** as a knowledge source: `.md` upload (and direct paste) with size and format validation, immediately available, excluded from URL re-sync and from customer-visible citation links.
- Harden **customer-visible source URL validation** used by citations: only web-backed documents are eligible, the link must be a well-formed `http(s)` URL without embedded credentials, its host must resolve, and every resolved address must be publicly routable.

## Capabilities

### New Capabilities

- `pilot-knowledge-auto-sync`: Scheduled and manual refresh of URL-backed Pilot knowledge documents with fingerprint-based change detection, configurable cadence with jittered execution, enqueue caps, permanent/transient failure classification, and sync state surfaced over the API.
- `pilot-knowledge-markdown-documents`: Markdown files (and pasted markdown) as a Pilot knowledge source type with validation, immediate availability, and correct exclusion from URL re-sync and citation links.
- `pilot-citation-source-url-validation`: Network-level eligibility checks deciding whether a knowledge document's source link may be shown to customers as a citation URL.

### Modified Capabilities

- `pilot-response-citations` (from change `pilot-agent-sessions-and-citations`): the trusted-URL resolution gains the network-level eligibility rules from `pilot-citation-source-url-validation`; no other behavior changes.

## Impact

- `Pilot::Document` model (`app/models/pilot/document.rb`): new metadata-backed fields (content fingerprint, last failure category, current refresh phase), file-backed vs web-backed classification, citation URL eligibility, sync-state helpers.
- `Pilot::Documents::SyncSchedulerJob` (`app/jobs/pilot/documents/sync_scheduler_job.rb`): cadence-aware eligibility, per-document jittered enqueueing, unchanged caps; `config/schedule.yml` comment updates.
- New per-document refresh service + job under `app/services/pilot/` and `app/jobs/pilot/documents/` (single-page refetch, fingerprint compare, failure classification); existing `Pilot::Documents::CrawlJob` keeps initial-ingestion role.
- `Custom::Pilot::DocumentIngestionService`: error taxonomy extended so fetch failures carry a permanent/transient classification.
- `Api::V1::Accounts::Pilot::DocumentsController`: manual refresh action, markdown params, sync-state filters and fields in list/show payloads.
- `pilot_documents` table: new composite index for scheduler/filter queries (no new tables; metadata `jsonb` absorbs the new fields).
- Account-level sync cadence setting (storage surface flagged in design open questions).
- Frontend: Pilot documents list/row components, add-document dialog (markdown upload), document settings (cadence, refresh-now), English i18n only.
