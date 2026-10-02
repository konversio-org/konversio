## Tasks

### Backend

#### Outbound fetch & webhooks

1. - [x] **SafeFetch module** — port upstream v4.18.0 `lib/safe_fetch.rb` plus new `lib/safe_fetch/request_options.rb`, `lib/safe_fetch/fetcher.rb`, `lib/safe_fetch/private_network_request.rb`; keep the existing error class contract, add `UnsupportedMethodError`, `SafeFetch.allow_private_network?` (`SAFE_FETCH_ALLOW_PRIVATE_NETWORK` env), content-type allowlist options, sensitive-header defaults (`authorization`, `cookie`, `proxy-authorization`), and per-request method/body/basic-auth support.
2. - [x] **Webhook delivery over SafeFetch** — rewrite `Webhooks::Trigger#perform_request` in `lib/webhooks/trigger.rb` to POST via `SafeFetch.fetch(..., method: :post, validate_content_type: false)`; keep `X-Konversio-Delivery/Timestamp/Signature` headers; map `SafeFetch::HttpError` to status for agent-bot retry on 429/500 (`RetryableError`); preserve `update_conversation_status` / `update_message_status` failure handling and the `WEBHOOK_TIMEOUT` global config (default 5s, split into open/read timeouts).
3. - [x] **Webhook payload enrichment** — add `Inbox::EventDataPresenter#webhook_data` (`push_data.merge(account: account.webhook_data)`) and switch `WebhookListener#inbox_created` / `#inbox_updated` to it (upstream `app/presenters/inbox/event_data_presenter.rb`, `app/listeners/webhook_listener.rb`).
4. - [x] **API/webhook gate** — add `Account#api_and_webhooks_enabled?` (`false` when the account is suspended, `true` otherwise); enforce in `Api::V1::Accounts::BaseController#validate_token_api_access` (403 `'API access is not enabled for this account'`), `Api::V1::AccountsController#validate_token_api_access`, `Api::V1::Accounts::Conversations::DirectUploadsController`, and short-circuit `WebhookListener#deliver_account_webhooks`.
5. - [x] **Slack inbound signature verification** — in `app/controllers/api/v1/integrations/webhooks_controller.rb` add `prepend_before_action :verify_slack_signature!`: read `SLACK_SIGNING_SECRET` via `GlobalConfigService.load` with ENV fallback; skip-with-warning when unset; otherwise require `X-Slack-Request-Timestamp` within 5 minutes and constant-time-compare `v0=<hmac-sha256>` over `v0:timestamp:` + raw request bytes; 401 on failure.
6. - [x] **Slack alerts-only mode** — add `Integrations::Hook#slack_alert_mode?` (`settings['message_mode'] == 'alert'`); make `Integrations::Slack::IncomingMessageBuilder` ignore inbound Slack messages when the hook is in alert mode; expose the mode in the Slack integration settings schema.

#### Upload, media, rendering, CSV

7. - [x] **Active Storage hardening initializer** — create `config/initializers/active_storage.rb` (port upstream): extend `content_types_allowed_inline` with the audio types list; prepend `ActiveStorageDirectUploadMetadataFilter` (strip `identified`/`analyzed`/`composed` from blob args); prepend `ActiveStorageProxyRangeLimit` (max 1 range, 100 MB chunk cap, `range_not_satisfiable` otherwise); include `ActiveStorageBareDirectUploadGuard` (403 for `instance_of?(ActiveStorage::DirectUploadsController)`, scoped subclasses exempt).
8. - [x] **Attachment allowlist: XML/PFX** — update `app/models/attachment.rb`: add `text/xml`, `application/xml`, `application/x-pkcs12`, `application/pkcs12` to `ACCEPTABLE_FILE_TYPES`; add `ACCEPTABLE_FILE_EXTENSIONS = %w[pfx xml]` and `GENERIC_FILE_CONTENT_TYPES = %w[application/octet-stream]`; accept generic/blank content type when the extension is allowlisted; add `inline_audio_url` and include `data_url` in push event data for audio (upstream reference).
9. - [x] **Markdown/HTML rendering sanitization** — add `lib/markdown_renderer_url_sanitizer.rb` (block `javascript:`, `vbscript:`, `file:`, `data:` except `data:image/{png,gif,jpeg,webp}`) and include it in `lib/base_markdown_renderer.rb`; port bounded `cw_image_width`/`cw_image_height` handling (`\A\d+px\z`, 1–2000) rendered as inline style; mirror the same URL rules in `app/javascript/shared/helpers/HTMLSanitizer.js`.
10. - [x] **CSV export safety sweep** — confirm every CSV export path uses `CSVSafe` (`app/jobs/account/contacts_export_job.rb`, all `app/views/**/*.csv.erb`); port the contacts export job changes: virtual `labels` column limited to account-owned label titles, header allowlist preserving requested order, UTF-8 BOM prepend.

#### Sessions & sign-in

11. - [x] **Session cookie hardening** — `config/initializers/session_store.rb`: add `httponly: true` and `secure:` bound to `FORCE_SSL` (keep the existing cookie key).
12. - [x] **user_sessions table + model** — migration for `user_sessions` (user FK, `client_id`, user agent, browser/platform/device name+version, ip, country/city/country_code, `last_activity_at`; unique index on `(user_id, client_id)`); port `app/models/user_session.rb` (`ACTIVITY_THROTTLE = 5.minutes`, `current?`, `should_update_activity?`).
13. - [x] **Session tracking service** — port `app/services/user_session_tracking_service.rb` and `app/controllers/concerns/track_session_activity.rb` (after_action, skip without `client` header, warn-and-continue on failure); include the concern in the base API controller stack; add `User#sync_user_sessions` (`after_save` on token change) pruning stale rows.
14. - [x] **Profile sessions API** — port `app/controllers/api/v1/profile/sessions_controller.rb` (index limited to active-token client ids, destroy revokes the DTA token and the row, 422 when revoking the current session) plus routes and jbuilder views.
15. - [x] **Sign-in hardening** — port `app/controllers/devise_overrides/sessions_controller.rb` changes: `merge_credential_headers` before_action; `render_create_error_not_confirmed` with `error_code: 'user_not_confirmed'`; `MAX_USER_SESSIONS` (default 25) enforcement on password, SSO, and MFA paths with oldest-session eviction (untracked tokens evicted first); browser 409 session-picker with `revoke_session_id` / `revoke_all_sessions`; impersonation handling (2-day token lifespan, `make_room_for_impersonation_token`, `sso_auth_token_impersonation?`).
16. - [x] **Redis::SecureStorage** — port `lib/redis/secure_storage.rb` (AES-256-GCM via `ActiveSupport::MessageEncryptor`, `EncryptionNotConfigured` error, nil on invalid message); identify and migrate plain-Redis secret stashes (needs investigation: exact upstream call sites in v4.18.0).

#### Access control & limits

17. - [x] **Rack::Attack throttle set** — update `config/initializers/rack_attack.rb`: normalized `path_without_extensions` (strip trailing slashes); widget conversations (30/min) and messages (60/min) keyed `"#{ip}:#{website_token}"` using ActionDispatch param precedence; widget contact (60/hour), widget load without `cw_conversation` (200/hour), transcript (5/hour); per-account throttles for conversation DELETE (60/min), agent POST incl. `bulk_create` (100/day), agent DELETE (50/day); reports drilldown throttle keyed on uid-or-api-token (limit = max(`RATE_LIMIT_REPORTS_API_USER_LEVEL`/10, 1)/min); all behind `ENABLE_RACK_ATTACK_*` / `RATE_LIMIT_*` env overrides with upstream defaults.
18. - [x] **Agent-bot endpoint allowlist** — extend `BOT_ACCESSIBLE_ENDPOINTS` in `app/controllers/concerns/access_token_auth_helper.rb` with `conversations#show` and `conversations/labels#index,#create`; keep `validate_bot_access_token!` denial for everything else; confirm `AgentBot.accessible_to(Current.account)` scoping on `AgentBotsController` and `InboxesController#fetch_agent_bot` (partially present).
19. - [x] **Dashboard app authorization** — add `before_action :check_authorization` to `Api::V1::Accounts::DashboardAppsController` with a `DashboardAppPolicy` (admin-only manage; port upstream `app/policies/dashboard_app_policy.rb`).
20. - [x] **Participant validation** — port `app/controllers/api/v1/accounts/conversations/participants_controller.rb`: coerce `user_ids` to integers, reject IDs not in `conversation.inbox.assignable_agents` with 422 `'Invalid participant IDs'`, use `find_or_create_by!`, and dispatch the unread-count-change event when membership changes (behind the unread-count feature flags).
21. - [x] **Agent & inbox limits with locking** — move limit enforcement into `AgentBuilder` under `account.with_lock` (`LimitExceededError`, upstream message), reserve invitation e-mail capacity for new users (`CustomExceptions::Account::EmailLimitExceeded`); update `AgentsController#create`/`bulk_create` to render `payment_required` on `LimitExceededError` and wrap bulk creation in one account lock; add inbox-creation limit raising `CustomExceptions::Inbox::LimitExceeded` (new `lib/custom_exceptions/inbox/limit_exceeded.rb`).
22. - [x] **Outbound e-mail limits** — port `app/models/concerns/account_email_rate_limitable.rb` (Redis counter, 25-hour TTL, `ACCOUNT_EMAILS_LIMIT` config key, `reserve_email_send_capacity` with WATCH/MULTI) and `CustomExceptions::Account::EmailLimitExceeded` (429); apply wherever outbound e-mail is sent or invitations are created — with the cloud-tier check removed so configured limits apply on self-hosted installs.
23. - [x] **Suspension metadata validation** — port `SuperAdmin::AccountsController` changes: require category (`Account::SUSPENSION_CATEGORIES`) and reason (≤ 256 chars) when setting an account to suspended, re-render edit with 422 on invalid metadata, and append suspension history entries.

#### Email channel configuration

24. - [x] **IMAP authentication mechanism** — migration adding `imap_authentication` (string, default `plain`) to `channel_email`; add to `Channel::Email::EDITABLE_ATTRS`; port `app/services/imap/authentication.rb` (`plain`/`login`/`cram-md5`, `validate_user_configurable!`, `authenticate!` using the IMAP LOGIN command for `login`); use it in `Api::V1::InboxesHelper#validate_imap` and `Imap::FetchEmailService`; expose in `app/views/api/v1/models/_inbox.json.jbuilder`.
25. - [x] **SMTP independent of IMAP** — restructure `Api::V1::InboxesHelper` so `validate_imap` and `validate_smtp` run independently of each other; verify `ConversationReplyMailer` sends when only SMTP is enabled (`email_smtp_enabled?` path) and IMAP fetch only runs when `imap_enabled`; port `smtp_timeout_settings` (`SMTP_OPEN_TIMEOUT` default 15, `SMTP_READ_TIMEOUT` default 30) in `app/mailers/conversation_reply_mailer_helper.rb` for both plain and XOAUTH2 SMTP settings.

#### Widget identity verification

26. - [x] **HMAC on identity-binding only** — update `app/controllers/api/v1/widget/contacts_controller.rb`: add `validate_hmac_for_identified_update` (only when `identifier` present), keep anonymous pre-chat updates working on `hmac_mandatory` inboxes, length-check before `secure_compare` (upstream v4.18.0 reference).
27. - [x] **Identity secret rotation** — add `POST /api/v1/accounts/:account_id/inboxes/:id/rotate_hmac_token` (member route) via a new `Api::V1::Accounts::Concerns::InboxSecretManagement` concern (move existing `reset_secret` there); allow for web widget and API inboxes only, `regenerate_hmac_token`, render `:show`.

### Frontend

28. - [x] **IMAP/SMTP settings UI** — add an authentication-mechanism selector to `app/javascript/dashboard/routes/dashboard/settings/inbox/ImapSettings.vue` (`plain` default; writes `imap_authentication`); make `SmtpSettings.vue` usable and savable without enabling IMAP; update the settings form validation copy (`en.json` only).
29. - [x] **Sessions management UI** — profile settings page listing active sessions (device, browser, location, last activity) with per-session revoke and current-session marking, backed by the new profile sessions API (`en.json` only).
30. - [x] **Session-limit picker** — handle the sign-in 409 response: show active sessions and offer "revoke selected" / "revoke all and sign in" actions posting `revoke_session_id` / `revoke_all_sessions` (needs investigation: fit into the current login flow, see design Open Questions).
31. - [x] **Slack alert mode toggle** — add a message-mode choice (two-way / alerts-only) to the Slack integration settings UI, persisted in hook `settings['message_mode']`.
32. - [x] **Widget identity verification UI** — show the identity-verification secret in web widget inbox settings with a "rotate" action calling `rotate_hmac_token`, with confirmation copy warning that existing `identifier_hash` signatures must be regenerated (`en.json` only).

### Validation

33. - [x] **SafeFetch specs** — port/extend upstream `spec/lib/safe_fetch*` coverage: SSRF-blocked IPs raise `UnsafeUrlError`, private-network mode fetches when enabled, size cap raises `FileTooLargeError`, content-type rejection, sensitive-header stripping on cross-origin redirect, CRLF rejection.
34. - [x] **Webhook trigger specs** — delivery goes through SafeFetch, 429/500 raise `RetryableError` for agent bots, signature headers present with secret, gate blocks delivery for suspended accounts.
35. - [ ] **Request specs** — Slack signature (valid/invalid/missing-secret-skip), alert mode drops inbound sync, participants 422 on non-assignable users, dashboard apps 403 for non-admins, profile sessions index/destroy, sign-in session limit (eviction + picker), `api_and_webhooks_enabled?` 403s.
36. - [ ] **Model/job specs** — attachment XML/PFX acceptance and generic-content-type fallback, `Imap::Authentication` mechanism validation, `AgentBuilder` limit under lock, `AccountEmailRateLimitable` reservation semantics, markdown sanitizer URL blocking, contacts export BOM/labels/header allowlist.
37. - [ ] **Rack::Attack specs** — new throttle discriminators (IP+token keying, per-account agent/conversation limits, drilldown user keying) and env override behavior.
38. - [ ] **Manual smoke tests** — widget on an `hmac_mandatory` inbox (anonymous pre-chat works, identified update without hash fails, with hash works, rotation invalidates old hashes); email inbox with SMTP-only (send works, no fetch errors); email inbox with `login` and `cram-md5` IMAP against a test server; Slack integration with secret set (bad signature 401) and alert mode (no inbound sync).

## Dependencies / Order

- Task 1 blocks 2, 33, 34 (everything SafeFetch). Tasks 3–6 are independent of 1–2 and of each other.
- Tasks 7–10 are independent; 10 should land after confirming which views already use `CSVSafe`.
- Tasks 12 → 13 → 14 → 15 are sequential (table, tracking, API, enforcement); 30 depends on 14–15. Task 11 and 16 are independent.
- Task 17 is independent; tasks 18–23 are independent of each other except 21 ↔ 22 (e-mail capacity reservation is called from `AgentBuilder`).
- Tasks 24–25 touch the same helper file and should be done together; 28 depends on 24–25.
- Tasks 26 → 27 (rotation UI 32 depends on 27).
- Validation tasks 33–37 run with their respective groups; 38 runs last.
