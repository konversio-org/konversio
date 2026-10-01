## Capability: integration-data-imports

Provider-agnostic, API-driven data import framework: credential validation, staged background import with resumable cursors, idempotent record mapping, per-item outcome tracking, error/skip logging, operator controls (start, retry, restart, abandon), placeholder inboxes, an administrator-only REST API, and a settings UI.

---

## ADDED Requirements

### Requirement: Integration import creation with credential validation

The system SHALL allow an administrator to create an integration import for a supported source provider (`intercom`, `freshdesk`) by supplying the provider's credentials and selecting at least one import type (`contacts`, `conversations`). Credentials MUST be validated against the source API before the import record is created, and the validation response SHOULD include expected record totals when the source API provides them. The access credential MUST be stored encrypted when application encryption is configured.

#### Scenario: validate_source with valid credentials

- Given the `data_import` feature is enabled for the account
- And the administrator supplies a valid `source_provider`, credential, and import types
- When `POST /api/v1/accounts/:account_id/data_imports/validate_source` is called
- Then the response is `{ valid: true }` with any available per-type record totals

#### Scenario: validate_source with invalid credentials

- Given the administrator supplies a credential the source API rejects
- When `validate_source` is called
- Then the response is `422` with `valid: false` and a message indicating the credential could not be validated

#### Scenario: validate_source with unsupported provider or missing parameters

- Given the administrator supplies an unsupported `source_provider`, a blank credential, or no import types
- When `validate_source` or `create` is called
- Then the response is `422` with `valid: false` and a parameter-specific message

#### Scenario: create enqueues the import

- Given valid source parameters
- When `POST /api/v1/accounts/:account_id/data_imports` is called
- Then a `DataImport` is created with `status: pending`, `source_type: api`, the selected `import_types`, initial zeroed stats, and a fresh active run id
- And the provider's import job is enqueued with that run id

#### Scenario: only one active integration import per account

- Given the account already has an integration import in `pending` or `processing` status
- When the administrator attempts to create another integration import
- Then no new import is created
- And the response is `422` stating another data import is already in progress

---

### Requirement: Staged, resumable background import

The system SHALL process an integration import as a chain of background jobs, one source-API page per job, on a low-priority queue. The contacts stage SHALL complete before the conversations stage begins. After each page the system MUST persist a cursor (`starting_after`, `completed`, `updated_at`) per stage so an interrupted import resumes where it stopped. The import record SHALL be touched at least once per minute while actively processing so liveness is observable.

#### Scenario: import progresses through stages

- Given a pending integration import with `import_types: ["contacts", "conversations"]`
- When the import job runs
- Then the import transitions to `processing` with `started_at` set
- And contacts pages are fetched and imported until the contacts cursor is `completed`
- And then conversation pages are fetched and imported until the conversations cursor is `completed`

#### Scenario: interrupted import resumes from cursor

- Given an import whose contacts cursor has a `starting_after` value and is not `completed`
- When the import job is re-enqueued
- Then contacts fetching resumes from the persisted cursor instead of the first page

#### Scenario: import completes cleanly

- Given all selected stages are cursor-completed and no errors or failures were logged
- When the last page job finishes
- Then the import transitions to `completed` with `completed_at` set
- And `total_records` and `processed_records` reflect the final stats

#### Scenario: import completes with errors

- Given the import logged at least one non-skip error or item failure during the run
- When the last page job finishes
- Then the import transitions to `completed_with_errors` and the stats `errors.count` reflects the logged errors

#### Scenario: unexpected job failure fails the import

- Given a page job raises an error that is not a source-client error and exhausts retries
- Then the import transitions to `failed` with `last_error_at` set
- And a run-level error log entry is recorded

---

### Requirement: Stale-run fencing and import stop conditions

The system MUST assign a fresh active run id on every create, restart, and retry, store it on the import record, and pass it to every enqueued job. A job whose run id no longer matches the import's active run id SHALL exit without side effects. Jobs and the importer SHALL also stop work at the next checkpoint when the import has been abandoned or has reached a terminal status.

#### Scenario: orphaned job from a previous run is a no-op

- Given an import that was restarted, giving it a new active run id
- When a job enqueued with the previous run id executes
- Then it performs no API calls and writes no records

#### Scenario: abandoned import stops in-flight work

- Given a processing import that is abandoned
- When the currently running page job reaches its next checkpoint
- Then it stops importing further records and does not re-enqueue

---

### Requirement: Idempotent record mapping and contact merging

The system SHALL record a mapping for every imported source object — unique per account, provider, object type, and source object id — pointing at the created Konversio record. Contacts MUST be matched to existing contacts by external identifier, then case-insensitive email, then E.164 phone number before a new contact is created; a matched contact SHALL be enriched only with attributes it lacks (name, email, phone, identifier, activity timestamps, merged additional/custom attributes). A source object already mapped by a previous import SHALL be marked `skipped` with an "already imported" log entry instead of being duplicated.

#### Scenario: contact matched by email is enriched, not duplicated

- Given the account has a contact with email `ada@example.com` and no name
- And the source returns a contact with email `ada@example.com` and a name
- When the import processes that contact
- Then no new contact is created
- And the existing contact's name is filled in and a mapping is recorded

#### Scenario: source object already imported by a previous import

- Given a completed import mapped source contact `123` to a Konversio contact
- When a new import encounters source contact `123`
- Then the import item is marked `skipped`
- And a skip log entry references the previous import and the mapped record

#### Scenario: re-running the same import does not duplicate records

- Given an import that already imported a conversation and its messages
- When the import is retried and reaches the same records
- Then conversation and message creation is skipped via identifier/source-id and mapping lookups
- And imported counts are reconciled, not incremented twice

---

### Requirement: Per-item outcomes and error/skip logs

The system SHALL track each source object as an import item with a status (`pending`, `processing`, `imported`, `skipped`, `failed`), an attempt count, and the last error code/message. Every skip, failure, and truncation SHALL be recorded as an import error entry with a machine-readable error code, a human-readable message, and structured details. Administrators MUST be able to download skip logs and error logs as CSV files.

#### Scenario: failed item is logged and import continues

- Given a source contact payload that fails to import
- When the importer processes it
- Then the item is marked `failed` with the error class and message
- And a `failed` log entry is recorded and `errors.count` is incremented
- And the remaining records on the page are still processed

#### Scenario: skip logs CSV download

- Given an import with skip log entries
- When `GET /api/v1/accounts/:account_id/data_imports/:id/skip_logs` is called
- Then a CSV is returned with columns `created_at, kind, source_object_type, source_object_id, error_code, message, details`

---

### Requirement: Operator controls — start, retry, abandon

The system SHALL let administrators restart a `failed` or `abandoned` import, retry a stalled import, and abandon an active import. An integration import untouched for 15 minutes while `pending` or `processing` MUST be reported as stalled (`stalled` in the API payload). Restart SHALL reset the run while retaining skip logs so previously skipped records stay skipped. Retry SHALL resume from the persisted cursor. All three actions MUST be rejected when another integration import is active, and MUST fail with a clear message when the stored credential is unavailable.

#### Scenario: restart a failed import

- Given a failed integration import with some skip logs
- When `POST .../data_imports/:id/start` is called
- Then the import returns to `pending` with lifecycle timestamps cleared and a new active run id
- And error logs are cleared while skip logs are retained and their counts seeded into stats
- And the import job is enqueued

#### Scenario: retry a stalled import

- Given a processing import whose `updated_at` is older than 15 minutes
- And no other integration import is active
- When `POST .../data_imports/:id/retry` is called
- Then the import returns to `pending` with a new active run id and is enqueued from its persisted cursor

#### Scenario: retry is rejected when the import is not stalled

- Given a processing import updated within the last 15 minutes
- When `retry` is called
- Then the response is `422` stating the import is no longer stalled

#### Scenario: abandon an active import

- Given a processing integration import
- When `POST .../data_imports/:id/abandon` is called
- Then the import transitions to `abandoned` with `abandoned_at` set
- And in-flight jobs stop at their next checkpoint

#### Scenario: start is rejected when credential is missing

- Given a failed import whose stored access credential is blank
- When `start` is called
- Then the response is `422` stating the credential is unavailable

---

### Requirement: Placeholder inboxes for imported conversations

The system SHALL route imported conversations into API-channel inboxes that it creates on demand, bucketed by the conversation's source type and named `"<Provider> Import - <Bucket>"`. Placeholder channels MUST be marked in `additional_attributes` as import placeholders with the provider, bucket, and a one-hour agent reply time window; the inboxes MUST have auto-assignment disabled, replies-after-resolve disabled, and default working hours. Existing placeholder inboxes for the same provider and bucket MUST be reused.

#### Scenario: placeholder inbox created on first use

- Given no placeholder inbox exists for the provider's `email` bucket
- When an imported conversation of that source type is processed
- Then an API inbox named e.g. "Intercom Import - Email" is created and used
- And subsequent conversations of the same bucket reuse it

---

### Requirement: Imported data semantics

Imported records SHALL be written without triggering application callbacks: no notifications, no auto-assignment, no automation. Imported conversations MUST be created in `resolved` status with source timestamps preserved (`created_at`, `updated_at`, `last_activity_at` derived from the latest imported message). Imported messages MUST carry `source_id` and external source ids keyed by provider, be attributed to the mapped contact when the author was a contact, map contact-authored parts to incoming and staff/bot-authored parts to outgoing, and mark source-platform notes as private. Attachments MUST NOT be downloaded; a message with attachments and no importable text SHALL include a placeholder note such as "[Intercom attachment skipped: 2]". Imported messages SHOULD be reindexed for search where search indexing is enabled.

#### Scenario: imported conversation is resolved and silent

- Given an import processes a source conversation
- When the Konversio conversation is created
- Then its status is `resolved`
- And its `created_at` matches the source creation time
- And no notification emails, webhooks, or automation rules fire for it or its messages

#### Scenario: private note maps to private message

- Given a source conversation part of type note
- When it is imported
- Then the resulting message has `private: true`

#### Scenario: attachment-only part becomes a placeholder message

- Given a source part with attachments and no body or subject text
- When it is imported
- Then the message content notes the number of skipped attachments

---

### Requirement: Administrator-only API and feature flag

All integration import endpoints and UI routes SHALL be gated by the `data_import` account feature flag and restricted to account administrators. Non-administrator users MUST receive an authorization error, and accounts without the flag MUST NOT be able to call the endpoints.

#### Scenario: agent cannot list imports

- Given a user with the agent role
- When they call `GET .../data_imports`
- Then the request is rejected as unauthorized

#### Scenario: feature flag disabled blocks access

- Given an account without the `data_import` feature
- When an administrator calls any data imports endpoint
- Then the request is rejected as unauthorized

---

### Requirement: Legacy contacts CSV import preserved

The existing contacts CSV import flow (file attachment processed by the legacy import job) MUST continue to work unchanged for imports with `data_type: 'contacts'` and no `source_provider`.

#### Scenario: CSV import still processes after upload

- Given an administrator uploads a contacts CSV
- When the import record is created
- Then the legacy `DataImportJob` is scheduled with a delay for the upload to settle
- And contacts are imported from the file as before
