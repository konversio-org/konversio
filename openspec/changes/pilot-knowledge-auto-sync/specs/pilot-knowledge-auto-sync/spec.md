## Capability: pilot-knowledge-auto-sync

Scheduled and manual refresh of URL-backed Pilot knowledge documents. A refresh fetches the document's own page, detects real content change via a stored fingerprint before rebuilding derived knowledge, classifies failures as permanent or transient, and runs on a per-account cadence with jittered execution and bounded enqueue volume.

---

## ADDED Requirements

### Requirement: fingerprint-based change detection

Every URL-backed document SHALL carry a content fingerprint — a hash of the whitespace-normalized page body — recorded after each successful fetch. A refresh MUST compare the newly computed fingerprint against the stored one before writing new content. The system SHALL update document content (and thereby trigger the existing knowledge-rebuild pipeline) only when the fingerprint differs.

#### Scenario: unchanged page performs no rebuild

- Given an available URL-backed document whose stored fingerprint matches the freshly fetched content
- When the refresh runs
- Then the document content is not written
- And no knowledge-rebuild job is enqueued
- And the document is marked synced with updated last-attempt and last-success timestamps

#### Scenario: changed page updates content and rebuilds knowledge

- Given an available URL-backed document whose stored fingerprint differs from the freshly fetched content
- When the refresh runs
- Then the document content and fingerprint are updated
- And the document name is refreshed from the fetched page title when one is present
- And the knowledge-rebuild pipeline runs via the existing content-change callback
- And the document is marked synced

#### Scenario: first refresh establishes a baseline without an update signal

- Given an available URL-backed document with no stored fingerprint
- When the refresh runs and the fetch succeeds
- Then the fingerprint is recorded
- And the refresh outcome is reported as unchanged/baseline, not as a content update

#### Scenario: fingerprint ignores whitespace-only differences

- Given a fetched page whose body differs from the stored content only in runs of whitespace
- When the fingerprint is computed
- Then it equals the stored fingerprint and the refresh reports no change

---

### Requirement: re-sync fetches only the document's own page

Scheduled and manual refreshes of a document SHALL fetch exactly the page identified by that document's source link. The multi-page site crawl SHALL remain reserved for initial document ingestion and MUST NOT be triggered by refreshes.

#### Scenario: scheduled refresh does not crawl

- Given an available URL-backed document originally ingested as part of a multi-page crawl
- When its scheduled refresh executes
- Then only the document's own URL is fetched
- And no new child documents are created

#### Scenario: file-backed documents are never refreshed

- Given a document backed by an uploaded PDF or markdown file
- When the scheduler evaluates eligibility or a manual refresh is requested
- Then the document is excluded from refresh
- And a manual refresh request for it is rejected with a client error

---

### Requirement: permanent and transient failure classification

The refresh pipeline SHALL classify every fetch failure as permanent or transient. Permanent failures — the target page no longer exists, access to it is refused, or the retrieved body is empty — MUST mark the document failed immediately without retrying. Transient failures — timeouts, connection or TLS errors, and upstream server errors — MUST be retried a bounded number of times on an increasing backoff before the document is marked failed. The failure category SHALL be recorded on the document in machine-readable form and cleared on the next successful refresh; the exact code values are an implementation detail.

#### Scenario: permanent failure fails fast

- Given an available URL-backed document whose page responds that it no longer exists
- When the refresh runs
- Then the document is marked failed with the corresponding failure category
- And the last-attempt timestamp is updated
- And the refresh job is not retried
- And the document keeps its previously synced content

#### Scenario: empty response body is permanent

- Given a fetch that succeeds at the transport level but yields no content
- When the refresh evaluates the result
- Then the failure is classified permanent and the document is marked failed without retry

#### Scenario: transient failure retries then fails

- Given an available URL-backed document whose host times out
- When the refresh job runs
- Then the job is retried on an increasing backoff up to its bounded attempt count
- And when attempts are exhausted the document is marked failed with the corresponding failure category
- And the document keeps its previously synced content

#### Scenario: transient failure recovers on retry

- Given a refresh that fails transiently on its first attempt
- When a later attempt succeeds
- Then the document is marked synced and any recorded failure category is cleared

#### Scenario: unexpected error is contained

- Given a refresh that raises an error outside the permanent/transient classification
- When the job's safety net handles it
- Then the document is marked failed with a generic failure category
- And the error is reported to exception tracking exactly once

---

### Requirement: per-account refresh cadence with jittered execution

Each account SHALL have a knowledge-refresh cadence of daily, weekly, or monthly, defaulting to daily, with an installation-wide default override. The scheduler SHALL run on its existing hourly tick and enqueue only documents whose cadence window has elapsed, using a due window of half the cadence so jittered executions never skip their next cycle. Each enqueued refresh SHALL be delayed by a random offset drawn from a window sized to the cadence (on the order of hours for daily, up to about a day for weekly, up to a few days for monthly). Manual refreshes SHALL NOT be delayed.

#### Scenario: document outside its cadence window is not enqueued

- Given an account on a weekly cadence with a document last synced two days ago
- When the scheduler tick runs
- Then the document is not enqueued

#### Scenario: due document is enqueued with a bounded random delay

- Given an account on a daily cadence with a document whose last sync is older than the due window
- When the scheduler tick runs
- Then a refresh job is enqueued for the document with a delay within the daily jitter window
- And the document's last-attempt timestamp is stamped at reservation time so a racing tick cannot double-enqueue it

#### Scenario: jittered execution does not skip the next cycle

- Given a document whose jittered refresh executed late within the previous window
- When the next scheduler window is evaluated
- Then the half-interval due window makes the document eligible again at the expected cadence

#### Scenario: stuck syncing documents are recovered

- Given a document in syncing state whose last attempt is older than the stale timeout
- When the scheduler tick runs
- Then the document is re-enqueued for refresh

---

### Requirement: bounded enqueue volume

The scheduler SHALL cap enqueues per tick at a per-account limit and a global limit (defaulting to the existing 50 and 1000 respectively), each overridable via installation configuration. Documents beyond the cap SHALL wait for a later tick, selected oldest-attempt-first.

#### Scenario: per-account cap defers excess documents

- Given an account with more due documents than the per-account cap
- When the scheduler tick runs
- Then only up to the cap are enqueued, oldest-attempt-first with never-attempted documents first
- And the remainder stay eligible for the next tick

#### Scenario: global cap stops the tick

- Given the global enqueue budget is exhausted by earlier accounts in the tick
- When the scheduler reaches the next account
- Then no further documents are enqueued that tick and the cap hit is logged

---

### Requirement: manual refresh endpoint

The documents API SHALL expose a per-document refresh action that marks the document syncing, clears the recorded failure category, enqueues an immediate refresh job, and returns 202. The action MUST reject documents that are file-backed or not in the available state.

#### Scenario: manual refresh enqueues immediately

- Given an available URL-backed document
- When an authorized user requests a manual refresh
- Then the response is 202 Accepted
- And the document shows syncing state with a current last-attempt timestamp
- And a refresh job is enqueued without jitter delay

#### Scenario: manual refresh rejected for ineligible documents

- Given a document that is file-backed, or whose ingestion is still in progress
- When a manual refresh is requested
- Then the response is a client error and no job is enqueued

---

### Requirement: sync state surfaced in the documents API

The documents list and detail payloads SHALL expose per-document sync status, last-attempt and last-success timestamps, the recorded failure category, the current refresh phase, and the account's effective cadence, and SHALL support filtering by sync state (stale, up-to-date, syncing, failed) and by source type (web, PDF, markdown).

#### Scenario: sync fields present in payloads

- Given documents in various sync states
- When the documents index is fetched
- Then each document carries its sync status, timestamps, failure category, and refresh phase
- And the payload includes the account's effective cadence

#### Scenario: stale filter matches cadence-aware staleness

- Given an account on a weekly cadence with a document last synced ten days ago
- When the documents index is filtered to stale
- Then that document is included
- And a document synced three days ago is not included
