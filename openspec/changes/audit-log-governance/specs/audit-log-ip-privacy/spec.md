## Capability: audit-log-ip-privacy

Privacy controls for the network addresses captured on audit entries: addresses are stored in full but masked by default in API responses, full disclosure is an explicit per-account opt-in, and coarse location (city, country) can be resolved asynchronously for display.

---

## ADDED Requirements

### Requirement: full storage, masked disclosure by default

Audit entries SHALL store the actor's full IP address at write time. API responses MUST mask the address unless the account has explicitly enabled the full-address flag. Masking keeps the network portion and blanks the host portion: for IPv4, the first three octets are kept and the final octet is replaced with a placeholder; for IPv6, the first four hextets are kept and the remainder is truncated. Blank or unparseable values MUST serialize as null rather than raising.

#### Scenario: IPv4 address is masked

- Given an audit entry recorded from "203.0.113.7"
- And the account has not enabled full addresses
- When the entry is listed
- Then the response shows the address as "203.0.113.x"

#### Scenario: IPv6 address is masked

- Given an audit entry recorded from "2001:db8:85a3:8d3:1319:8a2e:370:7348"
- And the account has not enabled full addresses
- When the entry is listed
- Then the response shows only the first four hextets followed by the truncation marker

#### Scenario: unparseable value serializes as null

- Given an audit entry whose recorded address is not a valid IP
- When the entry is listed
- Then the address field is null and no error is raised

---

### Requirement: opt-in full-address flag

The system SHALL provide a per-account feature flag that, when enabled, causes audit log API responses to return the full recorded IP address instead of the masked form. The flag MUST default to off.

#### Scenario: flag enabled returns full address

- Given an audit entry recorded from "203.0.113.7"
- And the account has enabled the full-address flag
- When the entry is listed
- Then the response shows the address as "203.0.113.7"

#### Scenario: stored value is never destructively masked

- Given an entry listed with masked addresses
- When the account later enables the full-address flag
- Then the same entry lists with its complete original address

---

### Requirement: asynchronous geolocation resolution

When an audit entry is created with a remote address and its account has IP lookup enabled, the system SHALL enqueue a low-priority background job that resolves the address to city, country, and country code and writes them to the entry. Resolution MUST use the existing core IP lookup service, MUST be a no-op when the GeoIP database is not provisioned, and MUST never raise into or delay the audited action.

#### Scenario: entry is enriched after creation

- Given an account with IP lookup enabled and a provisioned GeoIP database
- When an audit entry is created with a remote address
- Then a background job resolves the address and the entry gains city, country, and country code values

#### Scenario: lookup disabled means no enrichment

- Given an account without IP lookup enabled
- When an audit entry is created with a remote address
- Then no geolocation job is enqueued for that entry

#### Scenario: missing database is a silent no-op

- Given the GeoIP database file is not present on the host
- When a geolocation job runs
- Then it completes without writing values and without raising

#### Scenario: lookup failure is logged, not raised

- Given the lookup service raises a timeout
- When a geolocation job runs
- Then the failure is logged and the job finishes without retrying into the audited flow

---

### Requirement: batched resolution for sign-in events

Because every entry of a single sign-in or sign-out event shares one address, the system SHALL resolve that address once and apply the result to the whole batch of entries, and only when at least one involved account has IP lookup enabled. Enqueueing this job MUST NOT be able to interrupt authentication.

#### Scenario: one lookup covers a multi-account sign-in

- Given a sign-in that produced audit entries for three accounts, at least one with IP lookup enabled
- When the batched job runs
- Then the address is resolved once and all three entries receive the same city, country, and country code

#### Scenario: no eligible account means no work

- Given a sign-in where none of the user's accounts has IP lookup enabled
- Then no batched geolocation job is enqueued

---

### Requirement: operator-triggered backfill

The system SHALL provide a rake task that enqueues a backfill job walking existing audit entries that have a remote address but missing location fields. The job MUST process bounded batches ordered by id with a short delay between batches, restrict itself to accounts with IP lookup enabled, and skip (logging) individual rows that fail, so one bad address cannot abort the run.

#### Scenario: backfill progresses by cursor

- Given 1200 existing entries with addresses and no location data
- When the backfill job runs
- Then entries are processed in batches of at most 500, each batch rescheduling the next from the last processed id
- And the run stops when a batch finds no remaining rows

#### Scenario: row failure does not abort the batch

- Given one entry whose address causes the lookup to raise
- When the backfill processes that batch
- Then the failure is logged, the remaining rows in the batch are still processed, and the next batch is still scheduled

---

### Requirement: location display in the UI

The audit log entry payload SHALL include a formatted location (city and country, blank parts omitted) whenever it has been resolved and full addresses are not being served. The settings page SHALL show the resolved location when present, falling back to the (possibly masked) address, and the column header MUST reflect whether the account is seeing locations or full IP addresses.

#### Scenario: resolved location is displayed

- Given an entry with city "Berlin" and country "Germany" resolved
- And the account has not enabled full addresses
- When the entry renders in the audit log list
- Then the location column shows "Berlin, Germany"

#### Scenario: unresolved entry falls back to masked address

- Given an entry with no resolved location
- When the entry renders in the audit log list
- Then the column shows the masked address

#### Scenario: partial resolution omits blank parts

- Given an entry with country resolved but no city
- When the location is formatted
- Then it contains only the country, with no dangling separator

#### Scenario: full-address mode shows addresses, not locations

- Given an account with the full-address flag enabled
- When entries render in the audit log list
- Then the column shows complete IP addresses and no location field is served
