## Context

Konversio's video-call integration is the Dyte integration inherited from the v4.13.0 fork base. Upstream Chatwoot v4.16.0 migrated this integration to Cloudflare RealtimeKit via PR #14752. RealtimeKit is Dyte's v2 API re-hosted by Cloudflare: the REST endpoints, request shapes, and response shapes are the same, but the base URL becomes Cloudflare's API (`https://api.cloudflare.com/client/v4`), auth becomes a Bearer API token, and resources are scoped under an account id and a RealtimeKit app id (`/accounts/{account_id}/realtime/kit/{app_id}/...`).

License axis: **MIT — verbatim port**. Upstream Chatwoot is MIT-licensed and this change touches only core-tree files (no `enterprise/` involvement), so PR #14752's diff (`/tmp/pr-14752.diff`) may be applied to Konversio directly, at code level, including specs and i18n strings. Where upstream's new copy contains "Chatwoot", Konversio's existing rebrand to "Konversio" is preserved instead.

Verified against the upstream tree: the files PR #14752 touches are unchanged between the PR and v4.18.0 (`git diff v4.13.0 v4.18.0` shows no follow-up edits to `lib/dyte.rb`, the processor service, the validator, the dyte controllers, `IntegrationHelper.js`, or `VideoCallButton.vue` beyond the PR itself). Konversio's current copies of `lib/dyte.rb` and `lib/integrations/dyte/processor_service.rb` are byte-identical to upstream v4.13.0; `app/models/integrations/hook.rb` differs only by the `Chatwoot.` → `Konversio.` rename and two removed comment lines; `config/locales/en.yml` carries Konversio rebrand edits.

## Goals / Non-Goals

**Goals:**

- Port upstream PR #14752 verbatim into Konversio so the video-call integration talks to Cloudflare RealtimeKit.
- Keep upstream's naming decisions: `dyte` app id, `/dyte` routes, `Dyte` lib class, `Integrations::Dyte::ProcessorService`, and existing i18n keys stay as-is.
- Preserve upstream's operational behavior: legacy Dyte hooks are grandfathered until their settings change; no data migration.
- Port upstream's new and updated specs along with the implementation (this is a port, not new-spec authorship).
- Keep Konversio branding in user-facing strings ("Konversio", not "Chatwoot").

**Non-Goals:**

- Renaming the integration, routes, classes, or i18n keys to `realtimekit` (pure diff for zero benefit, diverges from upstream).
- Migrating existing hook settings in the database (upstream has no migration; re-configuration is manual per the changelog note).
- Any other v4.14–v4.18 backports.
- Building or self-hosting a custom RealtimeKit meeting UI (see Open Question below).

## Decisions

### Mirror upstream's "keep the dyte id, swap the internals" approach

Upstream did not create a new integration — the `dyte` app id, controller names, routes, `Dyte` class, and i18n keys all remain; only the HTTP client internals, credential schema, and participant lifecycle changed. The port applies the same diff unchanged (modulo the `Konversio.` rebrand in `hook.rb` and rebranded en.yml copy).

Alternatives considered:
- Rebrand to a `realtimekit` integration with new routes/controllers/keys. Rejected: adds churn and permanent divergence from upstream for no functional gain, and would break upstream's grandfathering logic which keys off `app_id == 'dyte'`.

Rationale: smallest possible port; future upstream fixes to these files remain trivially diffable.

### Client auth and credential model

`lib/dyte.rb` constructs with `(account_id, app_id, api_token)`, raising `ArgumentError` when any is blank, and sends `Authorization: Bearer <api_token>` against `https://api.cloudflare.com/client/v4/accounts/{account_id}/realtime/kit/{app_id}/`. The hook's `settings` hash stores exactly these three keys, enforced by the updated JSON schema in `config/integration/apps.yml` (all three required, `additionalProperties: false`, `visible_properties: ['account_id', 'app_id']`).

Alternatives considered:
- Keep the legacy Basic-auth pair and translate server-side. Rejected: RealtimeKit requires the Cloudflare credential set; translation would not work.

### Participant token lifecycle (rejoin = refresh, not re-create)

`add_participant_to_meeting` uses a namespaced client id (`"User:42"` / `"Contact:7"`) and, given the integration message, checks `content_attributes.data.participants[client_id]` first: a stored participant id gets a token refresh (`POST meetings/{id}/participants/{participant_id}/token`) and returns immediately. On creation, the returned participant id is persisted back onto the message (via `update_columns` to skip validations; failures logged, not raised). If creation fails because the participant already exists, the service falls back to listing meeting participants (`GET meetings/{id}/participants`), matching by `custom_participant_id`, and refreshing that participant's token.

Rationale (upstream's): RealtimeKit participant tokens are short-lived; re-creating participants on every join loses meeting state and errors on duplicate custom ids. Persisting the participant id on the integration message makes rejoin idempotent across both the dashboard (agent) and widget (contact) entry points, which is why both controllers now pass `@message` into the service.

### Preset-name compatibility retry

Participants are added with the Cloudflare-format preset name `group-call-host`; if the provider response contains a preset-not-found error, the request is retried once with the legacy Dyte-format name `group_call_host`.

Rationale (upstream's): apps migrated from Dyte to Cloudflare may carry the legacy underscore-format preset; the retry keeps both generations of apps working without configuration.

### Legacy-hook grandfathering and short-circuit

`Integrations::Hook` skips both the settings JSON-schema validation and the Cloudflare credential validation for persisted `dyte` hooks whose stored settings still look legacy (any of `organization_id`/`api_key` present, none of `account_id`/`app_id`/`api_token` present) and whose settings are not being changed. Credential validation runs only on create, on credential change, or on status toggle. At call time, `Integrations::Dyte::ProcessorService` short-circuits meeting creation and participant joins with a localized error (`errors.dyte.realtimekit_credentials_required`, telling the user to delete the Dyte integration and re-create it with Cloudflare credentials) whenever any of the three new credential keys is blank.

Alternatives considered:
- Data migration rewriting legacy settings. Rejected: legacy Dyte credentials cannot be converted into Cloudflare credentials; upstream documented manual re-configuration in the changelog instead.
- Hard-failing legacy hooks on boot or via a validation sweep. Rejected: upstream deliberately leaves them readable/untouched until edited.

### Credential validation at hook save time

The new `Integrations::Cloudflare::RealtimeKitCredentialsValidator` (Faraday, 5s timeouts) verifies the API token via Cloudflare's token-verify endpoint, then pages the account's RealtimeKit apps listing (page size 50, paging via `total_count` when present, otherwise full pages) until the configured App ID is found. It returns a `Data.define(:success?, :error)` result with error atoms `:missing_credentials`, `:invalid_api_token`, `:invalid_account_or_permissions`, `:app_not_found`, `:verification_failed` (5xx and network errors map to the last of these), each with a dedicated `errors.cloudflare.realtimekit.*` message in `en.yml`; the hook model adds the message as a base error, so the hooks API returns 422 with the specific reason.

Alternatives considered:
- Validate lazily on first call. Rejected: bad credentials would surface only as failed calls; save-time validation matches the existing OpenAI key validation pattern in the same model.

### Frontend: join URL and error surfacing only

The meeting join URL base moves to the Cloudflare-hosted RealtimeKit meeting page (`https://examples.realtime.cloudflare.com/meeting/`) with the same `authToken`/`showSetupScreen`/`disableVideoBackground` query params, now built via `URLSearchParams`. `VideoCallButton.vue` surfaces the server-provided error message (falling back to the generic create-error string) on meeting-creation failure. The two integration logos are replaced with upstream's new images.

No frontend response-shape change is needed: verified against upstream v4.13.0 and v4.18.0, the dashboard `Dyte.vue` bubble and widget `IntegrationCard.vue` already read `data.token` before this migration — the response key change from `auth_token` to `token` happens on the provider side and matches what the frontend already expects. (The plan's open question on this point is resolved.)

### i18n scope

Only `en.yml` is edited (per repo AGENTS.md; other locales are community-handled). New keys: `errors.dyte.realtimekit_credentials_required` and `errors.cloudflare.realtimekit.{missing_credentials,invalid_credentials,invalid_api_token,invalid_account_or_permissions,app_not_found,verification_failed}`. `integration_apps.dyte.name` becomes "Cloudflare RealtimeKit"; the description is upstream's new text with "Konversio" in place of "Chatwoot" (Konversio's rebranded `short_description` is kept).

## Risks / Trade-offs

- **Join page is Cloudflare's example app** -> Upstream points joins at `examples.realtime.cloudflare.com`, a hosted demo client. This is upstream's deliberate choice and is ported as-is; self-hosters wanting a fully self-contained call UI would need to host a RealtimeKit UI Kit app themselves — out of scope here.
- **`hook.rb` / `en.yml` merge drift** -> Konversio has local edits in both (rebrand, removed comments); the port merges by hand rather than applying the diff blindly.
- **Legacy hooks failing at call time** -> Intended upstream behavior; the short-circuit error message tells the user exactly how to recover (delete and re-add with Cloudflare credentials).
- **Preset retry doubles one failing request** -> Only fires on preset-not-found; bounded to a single retry.

## Migration Plan

1. Ship the port in a single release. No DB migration; no env vars.
2. Existing Dyte hooks keep validating as before until edited; call actions on them return the `realtimekit_credentials_required` error.
3. Admins delete the Dyte integration and add it again with Cloudflare Account ID, RealtimeKit App ID, and an API token with Realtime Admin permissions (per upstream's changelog note).
4. Rollback = revert the port; legacy Dyte settings were never mutated, so the old client works again as before.

## Open Questions

- needs investigation: whether Konversio wants to self-host a RealtimeKit meeting UI (UI Kit) instead of using Cloudflare's hosted example page for the join link. The port follows upstream (hosted example page); a self-hosted client would be a separate change with its own deployment story.
