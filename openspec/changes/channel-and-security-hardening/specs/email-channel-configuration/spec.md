## Capability: email-channel-configuration

Selectable IMAP authentication mechanisms on email channels, SMTP configuration and delivery independent of IMAP, and env-tunable SMTP timeouts.

---

## ADDED Requirements

### Requirement: Email channels support selectable IMAP authentication mechanisms

Email channel records SHALL store an IMAP authentication mechanism (default `plain`). Operators MUST be able to select `plain`, `login`, or `cram-md5`; any other value MUST be rejected before a connection is opened. The selected mechanism MUST be used consistently by both the inbox settings connection check and the background e-mail fetch service, with `login` using the IMAP LOGIN command rather than a SASL mechanism.

#### Scenario: default mechanism is plain

- Given a new email inbox with IMAP enabled and no mechanism selected
- Then the channel's IMAP authentication mechanism is `plain`

#### Scenario: invalid mechanism is rejected

- Given an operator submits `oauth2` as the IMAP mechanism for a non-OAuth channel
- When the inbox is saved
- Then validation fails listing the allowed mechanisms

#### Scenario: fetch service honors the stored mechanism

- Given a channel configured with the `cram-md5` mechanism
- When the fetch service connects
- Then authentication uses CRAM-MD5

#### Scenario: mechanism is exposed in the inbox API

- Given an email inbox with a configured mechanism
- When the inbox is fetched through the API
- Then the response includes the IMAP authentication mechanism

---

### Requirement: SMTP configuration is independent of IMAP

IMAP and SMTP validation on inbox create/update MUST run independently: each is performed only when its own enabled flag is set, and enabling one MUST NOT require or imply the other. Outbound replies for an email inbox MUST be deliverable whenever channel SMTP is enabled, regardless of IMAP state, and inbound fetching MUST run only when IMAP is enabled.

#### Scenario: SMTP-only inbox validates and sends

- Given an email inbox configured with SMTP enabled and IMAP disabled
- When the settings are saved
- Then only the SMTP connection is validated
- And outbound replies are delivered through the channel SMTP settings

#### Scenario: IMAP-only inbox validates and fetches

- Given an email inbox configured with IMAP enabled and SMTP disabled
- When the settings are saved
- Then only the IMAP connection is validated
- And inbound e-mail is fetched for the inbox

#### Scenario: failing IMAP check does not block a valid SMTP-only save

- Given an inbox with IMAP disabled and unreachable IMAP host details left in the form
- When the inbox is saved with valid SMTP settings
- Then the save succeeds

---

### Requirement: SMTP timeouts are env-configurable

SMTP open and read timeouts used for reply delivery MUST come from `SMTP_OPEN_TIMEOUT` and `SMTP_READ_TIMEOUT` environment variables with defaults of 15 and 30 seconds, applied to both plain SMTP and XOAUTH2 (OAuth provider) delivery settings.

#### Scenario: defaults apply when env vars are unset

- Given no SMTP timeout environment variables
- When a reply is delivered via channel SMTP
- Then the connection uses a 15-second open timeout and a 30-second read timeout

#### Scenario: env overrides apply to OAuth delivery too

- Given `SMTP_READ_TIMEOUT=60`
- When a reply is delivered through a Google or Microsoft OAuth channel
- Then the read timeout is 60 seconds
