## Capability: realtimekit-credentials-validation

Server-side verification of Cloudflare RealtimeKit credentials when a video-call (`dyte`) integration hook is created or its credentials change, ported verbatim (MIT) from upstream Chatwoot PR #14752 (v4.16.0). Validation distinguishes failure modes so admins get an actionable error instead of a broken integration.

---

## ADDED Requirements

### Requirement: Credential verification via Cloudflare's API

The validator (`Integrations::Cloudflare::RealtimeKitCredentialsValidator`) SHALL verify the API token against Cloudflare's token verification endpoint (`GET /client/v4/user/tokens/verify`, requiring HTTP 200 with a successful, active token status) and SHALL then confirm the configured RealtimeKit App ID exists in the account by paging the account's RealtimeKit apps listing (`GET /client/v4/accounts/{account_id}/realtime/kit/apps`, page size 50) until the app is found or the listing is exhausted. Network timeouts MUST be bounded (5 seconds). The result SHALL be a structured success/error value (`Result = Data.define(:success?, :error)`).

#### Scenario: all credentials valid

- Given a valid API token with Realtime Admin permissions, a valid account id, and an existing RealtimeKit app id
- When the validator runs
- Then it returns a successful result

#### Scenario: app found on a later page

- Given the configured app id appears on page 2 of the account's apps listing
- When the validator runs
- Then it pages through the listing and returns a successful result

---

### Requirement: Failure modes map to specific error atoms

The validator MUST report exactly one error atom per failure mode: `:missing_credentials` (any input blank, checked before any network call), `:invalid_api_token` (token verification rejects the token), `:invalid_account_or_permissions` (apps listing returns a non-200, non-5xx status), `:app_not_found` (listing exhausted without a match), and `:verification_failed` (5xx responses or network errors, which MUST also be logged). Each atom SHALL have a dedicated user-facing message under `errors.cloudflare.realtimekit.*` in `en.yml`.

#### Scenario: blank input short-circuits

- Given a blank account id, app id, or API token
- When the validator runs
- Then it returns `:missing_credentials` without making any HTTP request

#### Scenario: invalid token

- Given an API token that Cloudflare's verification endpoint rejects or reports inactive
- When the validator runs
- Then it returns `:invalid_api_token`

#### Scenario: wrong account or insufficient permissions

- Given a valid token but an account id the token cannot access for RealtimeKit
- When the validator runs
- Then it returns `:invalid_account_or_permissions`

#### Scenario: app not found

- Given valid token and account, but an app id absent from the account's apps listing
- When the validator runs
- Then it returns `:app_not_found`

#### Scenario: transient provider failure

- Given Cloudflare's API responds with a 5xx status or the request fails at the network layer
- When the validator runs
- Then it returns `:verification_failed`
- And the error is logged

---

### Requirement: Hook model validates credentials at the right moments

`Integrations::Hook` SHALL run Cloudflare RealtimeKit credential validation for `dyte` hooks only when the hook is enabled AND (it is newly created OR its credential settings changed OR its status is being toggled). On failure the hook MUST NOT save, the specific `errors.cloudflare.realtimekit.*` message MUST be added as a base error, and the hooks API MUST respond 422 with that message.

#### Scenario: creating a hook with valid credentials

- Given an admin creates a `dyte` hook with credentials the validator accepts
- When the hook is saved
- Then it persists successfully

#### Scenario: creating a hook with invalid credentials

- Given an admin creates a `dyte` hook with credentials the validator rejects as `:invalid_api_token`
- When the create request is submitted
- Then the hook is not created
- And the API responds 422 with the `errors.cloudflare.realtimekit.invalid_api_token` message

#### Scenario: editing unrelated attributes does not revalidate

- Given an existing enabled `dyte` hook
- When a non-credential attribute is updated without changing settings or status
- Then credential validation is skipped

---

### Requirement: Legacy Dyte hooks are exempt while untouched

The hook model SHALL skip both the settings JSON-schema validation and the Cloudflare credential validation for persisted `dyte` hooks whose stored settings match the legacy shape (any of `organization_id`/`api_key` present AND none of `account_id`/`app_id`/`api_token` present) as long as their settings are not being changed. Once such a hook's settings or status are edited, the new schema and credential validation MUST apply.

#### Scenario: legacy hook stays valid while untouched

- Given a persisted `dyte` hook with legacy `organization_id`/`api_key` settings
- When the record is re-saved without changing its settings
- Then no credential validation error is added

#### Scenario: legacy hook edited

- Given a persisted `dyte` hook with legacy settings
- When its settings are changed or its status is toggled
- Then the new credential schema and validator apply
- And invalid Cloudflare credentials block the save with the specific error message
