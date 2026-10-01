## Why

Teams migrating to Konversio from Intercom or Freshdesk need to bring their contact lists and historical conversations with them. Konversio today (fork base v4.13.0) only supports importing contacts from a CSV file — there is no way to import conversations, message history, or data pulled directly from a source platform's API.

Upstream Chatwoot addressed this across three releases: v4.16.0 added an API-driven Intercom import workflow for contacts and conversations, v4.16.2 hardened it with retry and reliability improvements (stall detection, resume, per-item tracking), and v4.17.0 extended the same framework to Freshdesk (contacts, tickets, replies, and private notes). All of this lives in the upstream core tree under the MIT license, so Konversio can port it directly.

## What Changes

- Extend `DataImport` beyond the legacy contacts-CSV flow: add `name`, `source_type`, `source_provider`, `import_types`, encrypted `access_token`, `source_metadata`, `stats`, `cursor`, lifecycle timestamps, and new statuses `completed_with_errors` and `abandoned`.
- Add three new tables: `data_import_items` (per-source-object outcome tracking), `data_import_mappings` (idempotent source-object → Konversio-record mapping), and `data_import_errors` (error and skip logs).
- Add a `DataImports::` framework: provider registry (`DataImports::Source`), `CreationService`, `RestartService`, `RetryService`, a shared paginated `Importer`, `MessageBatchBuilder`, and `PlaceholderInboxBuilder`.
- Add an Intercom provider (`DataImports::Intercom::*`): API client, credential validation, contact import, conversation import with activity-event messages, rate-limit-aware background jobs.
- Add a Freshdesk provider (`DataImports::Freshdesk::*`): domain + API key client, normalizer that reshapes tickets/replies/notes into the shared import payload, source-bucket routing, ticket-list pagination cap handling.
- Add a job chain (`DataImports::BaseJob` + import/contacts-page/conversations-page jobs per provider) that processes one page at a time with a persisted cursor, heartbeat, stale-run fencing, and `retry_on` for client and rate-limit errors.
- Route imported conversations into auto-created placeholder API inboxes bucketed by source type (e.g. "Intercom Import - Email").
- Add REST endpoints under `api/v1/accounts/:account_id/data_imports`: `index`, `show`, `create`, `validate_source`, `start`, `retry`, `abandon`, `skip_logs`, `error_logs`; gated by a new `data_import` account feature flag and an administrator-only policy.
- Add a Settings → Data UI: import list with status/progress, a new-import dialog (source, credentials, data types), and a detail page with summary tiles, progress, error and skip-log sections, CSV log downloads, and polling while active.
- The legacy contacts CSV import keeps working unchanged.

## Capabilities

### New Capabilities

- `integration-data-imports`: Provider-agnostic API-driven import framework — import lifecycle, staged pagination with resumable cursors, idempotent record mapping, per-item outcomes, error/skip logging, restart/retry/abandon, placeholder inboxes, admin API, and settings UI.
- `intercom-data-import`: Import contacts and conversations (including activity events) from Intercom via its REST API.
- `freshdesk-data-import`: Import contacts, tickets, public replies, and private notes from Freshdesk via its REST API.

### Modified Capabilities

None. The existing contacts CSV import (`data_type: 'contacts'` with an uploaded file) is preserved as the legacy path and its behavior is unchanged.

## Impact

- `data_imports` table (new nullable columns, migration required); new tables `data_import_items`, `data_import_mappings`, `data_import_errors`.
- `app/models/data_import.rb`, `app/models/data_import_item.rb`, `app/models/data_import_mapping.rb`, `app/models/data_import_error.rb`.
- `app/controllers/api/v1/accounts/data_imports_controller.rb`, `app/policies/data_import_policy.rb`, `app/finders/data_import_error_finder.rb`, `app/finders/data_import_skip_log_finder.rb`, jbuilder views for the endpoints, `config/routes.rb`.
- `app/jobs/data_imports/**`, `app/services/data_imports/**` (new namespaces; legacy `DataImportJob` and `DataImport::ContactManager` untouched except for a minor compatibility tweak).
- `lib/custom_exceptions/data_import/freshdesk_ticket_limit_error.rb`.
- `config/features.yml` (new `data_import` flag) and frontend `FEATURE_FLAGS`.
- Frontend: `app/javascript/dashboard/api/dataImports.js`, `app/javascript/dashboard/routes/dashboard/settings/data/**` (Index, Show, NewImportDialog, import components, route registration, i18n in `en.json`).
- Backend i18n: activity-event translations in `en.yml`.
- No changes to existing contacts, conversations, or messages behavior outside the import path; imported records are created via bulk inserts that skip callbacks and notifications.
