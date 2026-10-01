## Capability: session-and-signin-security

Hardened session cookie attributes, per-device session tracking with a profile revocation API, concurrent-session limits with eviction and a browser picker, sign-in hardening (credential header merging, distinct not-confirmed error), and encrypted transient secret storage in Redis.

---

## ADDED Requirements

### Requirement: Session cookie is httponly and secure under SSL

The application session cookie (used only for the super admin dashboard) MUST be set with `httponly: true`, `same_site: :lax`, and `secure: true` whenever SSL is enforced for the installation.

#### Scenario: cookie flags on an SSL-enforced install

- Given `FORCE_SSL` is enabled
- When a super admin signs in
- Then the session cookie carries `Secure`, `HttpOnly`, and `SameSite=Lax`

#### Scenario: local HTTP install keeps working

- Given `FORCE_SSL` is disabled
- When a super admin signs in over HTTP
- Then the session cookie is accepted by the browser (no `Secure` flag)

---

### Requirement: Per-device sessions are tracked

The system SHALL store one `user_sessions` row per (user, devise_token_auth client id) capturing user agent, browser/platform/device name and version, IP address, approximate location, and last activity time. Session activity MUST be refreshed at most once per 5 minutes per session, and failures in activity tracking MUST NOT break the request. Rows whose client id no longer exists in the user's tokens MUST be pruned automatically.

#### Scenario: sign-in creates a session row

- Given a user signing in with email and password
- When authentication succeeds
- Then a session row exists for the new client id with device and IP metadata

#### Scenario: activity update is throttled

- Given a session whose last activity was 1 minute ago
- When the user makes another API request
- Then the session's last activity timestamp is not rewritten

#### Scenario: revoked token removes the session row

- Given a user with a session row
- When the corresponding token is removed from the user's tokens
- Then the session row is destroyed

---

### Requirement: Users can list and revoke their sessions

A profile API SHALL expose the user's active sessions (limited to sessions whose tokens are still valid) ordered by most recent activity, marking the current session, and SHALL allow revoking any other session, which removes both the token and the session row. Revoking the current session through this API MUST be rejected with HTTP 422.

#### Scenario: list shows only live sessions

- Given a user with one expired token and one active token
- When the sessions endpoint is called
- Then only the session for the active token is returned

#### Scenario: revoking another session logs it out

- Given a user with sessions on two devices
- When the user revokes the other device's session
- Then that device's token no longer authenticates requests

#### Scenario: current session cannot be revoked

- Given a user calling the revoke endpoint for the session making the request
- Then the response is HTTP 422 with a cannot-revoke-current error

---

### Requirement: Concurrent sessions are capped with graceful eviction

The number of concurrently active sessions per user MUST be capped (default 25, configurable via `MAX_USER_SESSIONS`). When a password, SSO, or MFA sign-in would exceed the cap, the system MUST evict the oldest session — preferring untracked legacy tokens first, then the least-recently-active tracked session. Browser sign-ins where every token is tracked MUST instead receive an HTTP 409 response offering to revoke a chosen session or all sessions; non-browser clients MUST silently evict the oldest session.

#### Scenario: CLI client evicts oldest session silently

- Given a user at the session cap signing in from a non-browser client
- When authentication succeeds
- Then the oldest session is evicted and the sign-in completes

#### Scenario: browser user gets a session picker

- Given a browser user at the session cap with all sessions tracked
- When they sign in with valid credentials
- Then the response is HTTP 409 describing the active sessions

#### Scenario: revoke-all completes the sign-in

- Given the 409 picker response
- When the user retries with `revoke_all_sessions`
- Then all prior sessions are revoked and the sign-in completes

---

### Requirement: Sign-in handles credential headers and unconfirmed users explicitly

Before authentication, credential values supplied via request headers MUST be merged into the sign-in parameters so all pre-authentication checks observe the same credentials a header-only request would use. Sign-in attempts by users who have not confirmed their email MUST fail with HTTP 401 and a machine-readable `user_not_confirmed` error code.

#### Scenario: header-only sign-in is throttled like a body sign-in

- Given a client sending credentials only in headers
- When repeated failed sign-ins occur
- Then the login throttles apply exactly as for body-parameter requests

#### Scenario: unconfirmed user gets a distinct error code

- Given a registered but unconfirmed user signing in
- Then the response is HTTP 401 with `error_code: user_not_confirmed`

---

### Requirement: Sensitive transient data in Redis is encrypted

The system SHALL provide an encrypted Redis storage helper (AES-256-GCM authenticated encryption) for short-lived sensitive values, which refuses to operate when encryption keys are not configured and returns nil for undecryptable or malformed entries.

#### Scenario: round trip

- Given encryption is configured
- When a value is stored with a TTL and read back
- Then the original value is returned and the Redis payload is ciphertext

#### Scenario: missing encryption configuration raises

- Given encryption keys are not configured
- When a store is attempted
- Then an encryption-not-configured error is raised

needs investigation: the exact upstream v4.18.0 call sites that adopt this helper (which OAuth/SAML/onboarding flows store through it) must be confirmed during implementation; until then, only flows that currently stash secrets in plain Redis are migrated.
