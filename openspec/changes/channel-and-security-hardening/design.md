## Context

Konversio forked Chatwoot at v4.13.0 (upstream release 2026-04-16). Between v4.14.0 and v4.18.0 upstream shipped five releases of channel and security hardening. All referenced items live in upstream's MIT-licensed core tree — the `enterprise/` overlay was not needed for any of them except the SAML fixes, which target an EE-only feature Konversio does not ship.

Konversio has already absorbed a slice of this work during the fork: webhook secrets and HMAC signing (rebranded to `X-Konversio-Signature` / `X-Konversio-Timestamp` / `X-Konversio-Delivery` in `lib/webhooks/trigger.rb`), webhook subscription allowlisting including `inbox_created`/`inbox_updated`, `WebhookSecretable`, `Account#webhook_data`, `AgentBot.accessible_to`, the `csv-safe` gem with some views migrated, `HookPolicy`, and webhook/dashboard-app-adjacent policies. What remains is the larger structural work: the modular SafeFetch, webhook delivery over SafeFetch, upload/streaming guards, session tracking, the new throttle set, builder-level limits, IMAP auth options, SMTP/IMAP decoupling, Slack signature verification and alert mode, the API gate, markdown sanitization, and HMAC rotation.

Upstream reference points used (all MIT, verbatim porting is legal):

- `lib/safe_fetch.rb`, `lib/safe_fetch/{request_options,fetcher,private_network_request}.rb` @ v4.18.0
- `lib/webhooks/trigger.rb`, `app/listeners/webhook_listener.rb`, `app/presenters/inbox/event_data_presenter.rb` @ v4.18.0
- `config/initializers/{rack_attack,active_storage,session_store}.rb` @ v4.18.0
- `app/controllers/devise_overrides/sessions_controller.rb`, `app/controllers/api/v1/profile/sessions_controller.rb`, `app/models/user_session.rb`, `app/services/user_session_tracking_service.rb`, `app/controllers/concerns/track_session_activity.rb` @ v4.18.0
- `app/controllers/api/v1/integrations/webhooks_controller.rb` (Slack signature), `app/models/integrations/hook.rb` (`slack_alert_mode?`) @ v4.18.0
- `app/services/imap/authentication.rb`, `app/helpers/api/v1/inboxes_helper.rb`, `app/mailers/conversation_reply_mailer_helper.rb` @ v4.18.0
- `app/controllers/api/v1/widget/contacts_controller.rb`, `app/controllers/api/v1/accounts/concerns/inbox_secret_management.rb` @ v4.18.0
- `app/builders/agent_builder.rb`, `app/models/concerns/account_email_rate_limitable.rb`, `app/controllers/super_admin/accounts_controller.rb`, `app/controllers/api/v1/accounts/conversations/participants_controller.rb`, `app/models/attachment.rb`, `lib/markdown_renderer_url_sanitizer.rb` @ v4.18.0

## Goals / Non-Goals

**Goals:**

- Reach parity with upstream v4.18.0 for the assigned changelog items: webhook validation and SSRF hardening (v4.14.0), SafeFetch and private-network opt-in (v4.14.1/4.14.2), sessions/webhooks/OAuth/secrets fixes (v4.15.0), widget identity verification, agent-bot tokens, dashboard apps, inbox limits (v4.16.0), spam-protection gating, rate limits, hook deletion and token access (v4.16.1), participants/account/email limits (v4.16.2), uploads/account scoping/feature access/CSV exports (v4.17.0), sign-in/macros/webhooks/media/HTML hardening, SMTP independence, Slack alerts-only mode, and identity-verification secret rotation (v4.18.0).
- Keep Konversio's rebranding intact: webhook signature headers stay `X-Konversio-*`; no `Captain` naming anywhere; everything lands in the core tree.
- Preserve self-hosted operability: every new throttle, limit, and gate must be configurable or default-open so a fresh self-hosted install behaves like today.

**Non-Goals:**

- SAML. Upstream's SAML fixes (v4.14.0) touch `enterprise/app/builders/saml_user_builder.rb`, `enterprise/app/jobs/saml/update_account_users_provider_job.rb`, and `enterprise/config/initializers/omniauth_saml.rb` — an EE feature Konversio removed with the `enterprise/` overlay. If SAML is ever (re)introduced, the functional takeaways are: do not let a SAML login bind a user who belongs to other accounts, scope provider-migration jobs to users that actually belong to the account, gate custom-role assignment on the feature flag, and carry SAML request context in the OmniAuth env instead of the session cookie.
- Cloud/billing tier logic. Upstream gates several limits behind `ChatwootApp.chatwoot_cloud?` (`lib/konversio_app.rb` in Konversio). Konversio is self-hosted only; the mechanisms are ported but apply based on configuration, not cloud tier.
- WhatsApp/voice/Help-Center/company items from the same releases — covered by other change documents.
- No application-code implementation in this change; this is a spec and task plan.

## Decisions

### Port upstream MIT code verbatim where it exists

All assigned items are MIT. Where upstream's core tree contains the implementation (SafeFetch module, `Imap::Authentication`, rack-attack rules, the Active Storage initializer, `MarkdownRendererUrlSanitizer`, `UserSession` stack, `AccountEmailRateLimitable`, participants validation, Slack signature verification), the implementation agent should port the upstream files directly, adapting only names Konversio rebranded (`ChatwootApp` → `KonversioApp`, `Chatwoot.` helpers, `X-Chatwoot-*` → `X-Konversio-*`, `chatwoot-safe-fetch` tempfile prefix may stay or be renamed — cosmetic).

Alternatives considered: re-implementing from scratch to "clean" the code. Rejected — MIT permits verbatim porting, and staying textually close to upstream minimizes behavioral drift and eases future security audits against upstream advisories.

Rationale: legal, lowest-risk, fastest path to parity.

### Replace RestClient webhook delivery with SafeFetch delivery

`Webhooks::Trigger` currently POSTs via `RestClient`, which follows redirects without SSRF checks and does not cap response size. Upstream v4.18.0 delivers through `SafeFetch.fetch(method: :post, validate_content_type: false)` and maps `SafeFetch::HttpError` statuses for agent-bot retry (429/500). Port that shape: keep the existing `X-Konversio-*` signing headers, keep the error-handling contract (`SUPPORTED_ERROR_HANDLE_EVENTS`, pending-conversation re-open on agent-bot failure, message status `failed` for API inboxes).

Alternatives considered: keep RestClient and add a pre-flight SSRF check. Rejected — DNS-rebinding and redirect-chain gaps remain; SafeFetch's resolve-and-pin approach closes them.

Rationale: one fetch path for all outbound HTTP means one place to audit.

### Private-network fetching is an explicit, global, self-hosted opt-in

Upstream's "allowlist for private inbox webhooks" (v4.14.1) is `SAFE_FETCH_ALLOW_PRIVATE_NETWORK`: when set, `SafeFetch::PrivateNetworkRequest` performs the fetch without `ssrf_filter`'s public-IP restriction, but still validates scheme, strips sensitive headers on cross-origin redirects, rejects CRLF, and pins the resolved IP. It is a global env flag, not a per-inbox allowlist. Konversio adopts the same semantics.

Alternatives considered: a per-inbox or per-webhook allowlist UI. Rejected for this change — upstream chose the global flag, and self-hosted operators who need internal webhooks can set one env var.

Rationale: parity with upstream; simplest operable mechanism for the self-hosted audience.

needs investigation: whether upstream v4.18.0 has any per-endpoint refinement beyond the global env flag (none was found in the tree).

### Account-level API/webhook gate without cloud tier checks

Upstream v4.16.0/4.16.1's "spam-protection gating" adds `Account#api_and_webhooks_enabled?` (OSS returns `true`; EE overrides with suspension logic) and enforces it in `Api::V1::Accounts::BaseController#validate_token_api_access`, `Api::V1::AccountsController`, `Conversations::DirectUploadsController`, and `WebhookListener#deliver_account_webhooks`. Konversio ports the gate and all four enforcement points. The method returns `false` when the account is suspended (suspension status and `SUSPENSION_CATEGORIES` live in the MIT core `Account` model and super admin controller), `true` otherwise.

Alternatives considered: skip the gate because cloud spam protection does not apply to self-hosted. Rejected — super admins of multi-tenant self-hosted installs need the same kill switch, and the enforcement points are cheap.

Rationale: the gate is the MIT-visible part; the cloud-tier trigger is not needed.

### Session tracking reuses devise_token_auth tokens as the source of truth

`user_sessions` rows are keyed `(user_id, client_id)` where `client_id` is the devise_token_auth client header; `User#sync_user_sessions` prunes rows whose client ids no longer exist in `user.tokens`. Sign-in enforces `MAX_USER_SESSIONS` (default 25): non-browser clients silently evict the oldest session; browser clients with fully tracked sessions get a 409 picker that can revoke one session or all. Impersonation tokens get a 2-day lifespan and pre-eviction so they never push out a real session.

Alternatives considered: a separate session store independent of DTA tokens. Rejected — dual sources of truth drift.

Rationale: upstream's design keeps revocation and expiry aligned with the tokens the API actually accepts.

needs investigation: the exact upstream call sites of `Redis::SecureStorage` in v4.18.0 (which OAuth/SAML/onboarding flows store through it). Port the module; wire call sites only where the current flow already stashes secrets in plain Redis.

### Widget HMAC enforcement only on the identity-binding path

Anonymous pre-chat updates (name/email/phone/custom attributes, no `identifier`) must keep working on `hmac_mandatory` inboxes. HMAC is required only when an `identifier` is supplied (contact re-binding) or when `identifier_hash` is present. Hash comparison is length-checked then constant-time. Secret rotation is a new admin endpoint `POST /api/v1/accounts/:account_id/inboxes/:id/rotate_hmac_token` for web widget and API inboxes, implemented in a controller concern alongside `reset_secret`.

Alternatives considered: enforcing HMAC on every widget contact write (upstream v4.16.0's first cut). Rejected — it broke anonymous pre-chat; upstream itself narrowed it.

Rationale: matches the final upstream behavior and preserves anonymous widget UX.

### SMTP and IMAP are validated and used independently

`validate_imap` and `validate_smtp` in `Api::V1::InboxesHelper` each return early unless their own `_enabled` flag is set; an inbox can enable SMTP without IMAP and vice versa. Outbound replies use channel SMTP whenever `smtp_enabled`, independent of IMAP. IMAP authentication mechanism is a new `imap_authentication` column (`plain` default; `plain`, `login`, `cram-md5` selectable) validated before opening a connection and used identically by the fetch service. SMTP open/read timeouts come from `SMTP_OPEN_TIMEOUT` / `SMTP_READ_TIMEOUT` env vars with 15s/30s defaults.

Alternatives considered: keep the legacy coupling where SMTP validation ran only inside the IMAP flow. Rejected — operators increasingly run send-only (SMTP) or receive-only (IMAP) setups.

Rationale: parity with v4.18.0 and a real self-hosted need.

### Slack inbound signature verification degrades open, alert mode is per-hook

`SLACK_SIGNING_SECRET` unset → verification is skipped with a warning log (existing installs keep working). Set → requests must carry a valid `v0` HMAC-SHA256 signature over `v0:timestamp:raw_body` within a 5-minute tolerance, compared constant-time over raw bytes. Alerts-only mode is `hook.settings['message_mode'] == 'alert'`: conversations push to Slack, but Slack thread replies are never synced back.

Alternatives considered: rejecting requests when the secret is unset. Rejected — it would break every existing Slack install on upgrade; upstream deliberately chose skip-with-warning.

Rationale: opt-in hardening with a safe migration path.

### Rate limits are env-tunable with upstream defaults

New throttles use upstream default numbers (widget conversations 30/min, widget messages 60/min keyed on `ip:website_token`, widget contact 60/hour, widget load 200/hour, transcript 5/hour, conversation delete 60/min/account, agent create 100/day/account, agent delete 50/day/account, reports drilldown = max(reports limit / 10, 1)/min/user) with `RATE_LIMIT_*` / `ENABLE_RACK_ATTACK_*` overrides. Limits enforce agent/inbox caps inside `AgentBuilder`/inbox creation under `account.with_lock`, and outbound e-mail via a Redis counter with 25-hour TTL (`ACCOUNT_EMAILS_LIMIT` config key) applied whenever a limit is configured — not gated on cloud tier.

Alternatives considered: hardcoding upstream numbers. Rejected — self-hosted installs vary wildly in size.

Rationale: sane defaults, operator override, no surprise lockouts.

## Risks / Trade-offs

- **SafeFetch behavior change for existing webhook targets** -> private-network webhook endpoints (common in self-hosted) will start failing until the operator sets `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true`. Mitigate with upgrade notes and a clear `UnsafeUrlError` message.
- **Session-limit eviction surprise** -> users with many devices get oldest sessions evicted at 25. Mitigate with the browser picker and the env override.
- **Slack unsigned-webhook skip** -> signature verification is off until the operator configures the secret; document prominently.
- **`api_and_webhooks_enabled?` default** -> must stay `true` for active accounts or every integration breaks on deploy; only suspension flips it.
- **Cookie `secure` flag** -> only set when SSL is enforced (`FORCE_SSL`), otherwise local HTTP installs lose the super admin session.

## Migration Plan

1. Migrations: `user_sessions` table; `imap_authentication` column on `channel_email` (default `plain`). Both additive, no backfill required.
2. Deploy order: SafeFetch module first, then switch `Webhooks::Trigger` to it; enable new throttles with upstream defaults; ship session tracking, then the session-limit enforcement (tracking must exist before the picker path is meaningful).
3. Rollback: each capability is independently revertable; the SafeFetch switch is the only one with user-visible behavior change (private-network targets), gated by the env flag.

## Open Questions

- Should `RATE_LIMIT_*` values be surfaced in super admin installation configs, or are env vars sufficient for v1? Proposal assumes env vars, matching upstream.
- For the session-picker 409 flow, does Konversio's current login UI need a dedicated screen, or is the silent-eviction path enough for v1? needs investigation against the current frontend sign-in flow.
- Exact upstream v4.14.0 "admin auth checks" scope: the tree diff shows the policy/authorization additions covered here (dashboard apps, hooks, integrations base controller) but no single identifiable commit; treat as covered by the authorization items and flag any gap found during implementation.
