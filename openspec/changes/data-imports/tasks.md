## Tasks

All items are a verbatim-or-adapted port of upstream MIT code (see `design.md`). Upstream reference: `git -C /tmp/chatwoot-upstream diff v4.13.0 v4.18.0 -- <path>`.

### Backend

1. - [x] **Migration: expand `data_imports`** — port `db/migrate/20260702000000_expand_data_imports_for_intercom_imports.rb`: add `name`, `source_type`, `source_provider`, `import_types` (jsonb, default `[]`), `initiated_by_id`, `access_token` (text), `source_metadata`, `stats`, `cursor` (jsonb, default `{}`), `started_at`, `completed_at`, `abandoned_at`, `last_error_at`; indexes on `initiated_by_id` and `source_provider`.
2. - [x] **Migration: `data_import_items`** — port `db/migrate/20260702000001_create_data_import_items.rb`; unique index `(data_import_id, source_object_type, source_object_id)`, indexes on source and record.
3. - [x] **Migration: `data_import_mappings`** — port `db/migrate/20260702000002_create_data_import_mappings.rb`; unique index `(account_id, source_provider, source_object_type, source_object_id)` (name `idx_data_import_mappings_on_account_and_source` — the message upsert targets it).
4. - [x] **Migration: `data_import_errors`** — port `db/migrate/20260702000003_create_data_import_errors.rb`.
5. - [x] **Models** — port `app/models/data_import.rb` (expanded), `app/models/data_import_item.rb`, `app/models/data_import_mapping.rb`, `app/models/data_import_error.rb`. Preserve the legacy CSV path (`legacy_contacts_csv_import?`, `process_data_import` gating) and keep `DataImportJob` working for `data_type: 'contacts'` with no `source_provider`. Replace any `Chatwoot.` references with the Konversio equivalent (check `encrypts :access_token` guard).
6. - [x] **Framework services** — port `app/services/data_imports/source.rb` (provider registry), `creation_service.rb`, `restart_service.rb`, `retry_service.rb`, `importer.rb`, `message_batch_builder.rb`, `placeholder_inbox_builder.rb` verbatim where possible.
7. - [x] **Intercom provider** — port `app/services/data_imports/intercom/*` (client, credentials_validator, source, source_bucket, importer, message_batch_builder, activity_content_builder, placeholder_inbox_builder, creation/restart/retry subclasses).
8. - [x] **Freshdesk provider** — port `app/services/data_imports/freshdesk/*` (client, credentials_validator, source, source_bucket, ticket_page, normalizer, metadata, importer, message_batch_builder, placeholder_inbox_builder) and `lib/custom_exceptions/data_import/freshdesk_ticket_limit_error.rb`.
9. - [x] **Jobs** — port `app/jobs/data_imports/base_job.rb`, `import_job.rb`, `contacts_page_job.rb`, `conversations_page_job.rb`, and the per-provider subclasses under `app/jobs/data_imports/intercom/` and `app/jobs/data_imports/freshdesk/` (queue `:low`, `retry_on` for client/rate-limit errors with provider-specific waits, `discard_on` for the Freshdesk ticket-limit error).
10. - [x] **Controller + routes** — port `app/controllers/api/v1/accounts/data_imports_controller.rb` and add the `resources :data_imports` block (index/show/create + `validate_source`, `start`, `retry`, `abandon`, `error_logs`, `skip_logs`) to `config/routes.rb`.
11. - [x] **Policy + finders + views** — port `app/policies/data_import_policy.rb` (administrator-only), `app/finders/data_import_error_finder.rb`, `app/finders/data_import_skip_log_finder.rb`, and `app/views/api/v1/accounts/data_imports/*.json.jbuilder`.
12. - [ ] **Feature flag** — add `data_import` to `config/features.yml` (enabled by default for self-hosted; decide bit column — see design.md open question) and `FEATURE_FLAGS.DATA_IMPORT` to the frontend feature-flags module.
13. - [x] **Backend i18n** — port `data_imports.intercom.activities.*` translations and `errors.data_import.*` keys into `config/locales/en.yml` (en only per repo convention).
14. - [x] **Legacy compatibility check** — confirm `app/jobs/data_import_job.rb` and `app/services/data_import/contact_manager.rb` still process CSV imports end-to-end after the model changes (upstream touched `contact_manager.rb` by one line).

### Frontend

15. - [ ] **API client** — port `app/javascript/dashboard/api/dataImports.js` and register it in the API index.
16. - [ ] **Routes** — port `app/javascript/dashboard/routes/dashboard/settings/data/data.routes.js` (Index + Show under `settings/data`, feature-flagged, administrator permission) and register in the settings route tree; add the sidebar entry to the settings navigation.
17. - [ ] **Import list + dialog** — port `Index.vue` and `NewImportDialog.vue` (source picker from `importSources.js`, credential fields — access key for Intercom, domain + API key for Freshdesk — import-type checkboxes, validate-then-create flow).
18. - [ ] **Import detail page** — port `Show.vue` and `components/` (`ImportDetailHeader`, `ImportSummaryTiles`, `ImportProgress`, `ImportErrorsSection`, `ImportSkipLogsSection`, `ImportLogSection`) plus `importStatus.js` helpers and the 5s polling lifecycle; wire start/retry/abandon buttons and skip/error-log CSV downloads.
19. - [ ] **Frontend i18n** — port the new keys into `en.json` only.
20. - [ ] **Frontend specs** — port the upstream specs under `routes/dashboard/settings/data/specs/` (`importSources`, `importStatus`, `ImportDetailHeader`, `NewImportDialog`, `pollingLifecycle`, `showActions`).

### Validation

21. - [ ] **Backend specs** — port upstream specs for `DataImport` model, `DataImports::Importer`, creation/restart/retry services, both providers' clients/validators/normalizers, jobs, controller, and policy; run `bundle exec rspec spec/models/data_import* spec/services/data_imports spec/jobs/data_imports spec/controllers/api/v1/accounts/data_imports_controller_spec.rb`.
22. - [ ] **Legacy CSV regression** — run the existing CSV-import specs (`spec/jobs/data_import_job_spec.rb` and related) to prove the legacy path is untouched.
23. - [ ] **Lint** — `bundle exec rubocop -a` on ported Ruby, `pnpm eslint` on ported Vue/JS.
24. - [ ] **Manual smoke test (Intercom)** — with a test Intercom workspace: validate credentials, start a contacts+conversations import, watch progress/stats update, kill a worker mid-run and confirm Retry resumes from the cursor, abandon a run and confirm in-flight jobs stop, restart a failed run and confirm skip logs are retained and no duplicates are created.
25. - [ ] **Manual smoke test (Freshdesk)** — with a trial Freshdesk account: verify domain normalization (subdomain-only and full-URL input), contacts import, and a ticket with public replies + a private note → one resolved conversation with the note as a private message; verify skip-log CSV download.

## Dependencies / Order

Migrations (1–4) → models (5) → framework services (6) → providers (7, 8 in either order) → jobs (9) → controller/policy/views/routes (10, 11) → feature flag (12) → i18n (13). Task 14 runs any time after 5. Frontend (15–20) depends on 10–12 for the API contract but can be built in parallel against the upstream payloads. Validation (21–25) runs last; 22 must pass before merge.
