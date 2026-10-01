## Capability: audit-log-browsing

Admin-only API and settings UI for reviewing an account's audit trail: paginated listing with event-type filtering, actor search, a date window, and newest/oldest sorting, with filter state synchronized to the page URL.

---

## ADDED Requirements

### Requirement: admin-only, feature-gated listing endpoint

The system SHALL expose an account-scoped audit log listing endpoint restricted to administrators. When the account's audit logs feature flag is disabled, the endpoint MUST return an empty result set and log a warning, rather than an error.

#### Scenario: non-admin is rejected

- Given a user with the agent role
- When they request the audit log listing
- Then the request is denied

#### Scenario: feature disabled returns empty page

- Given an account without the audit logs feature enabled
- When an administrator requests the listing
- Then the response contains zero entries and pagination metadata
- And a warning is logged server-side

#### Scenario: entries are paginated at 25 per page

- Given an account with 30 audit entries
- When an administrator requests the first page
- Then the response contains 25 entries
- And the metadata reports the current page, 25 per page, and 30 total entries

---

### Requirement: entry payload shape

Each listed entry SHALL expose: id, auditable id and type, the auditable object payload (when applicable), account association, actor id/type and recorded username, action, recorded changes, version, comment, request identifier, creation time as a unix timestamp, and the actor's IP address subject to the masking rules of the `audit-log-ip-privacy` capability.

#### Scenario: message deletion entries are redacted

- Given a message deletion audit entry whose stored snapshot includes the original body
- When the entry is listed
- Then the response's auditable payload for that entry is null
- And the recorded changes in the response do not contain the message body
- And the recorded changes still identify the conversation's display number

---

### Requirement: event-type filtering

The endpoint SHALL accept an optional list of auditable types and return only entries matching those types. The UI SHALL present the supported types as a single-select filter organized into domain groups — sign-in activity; staff, team and inbox membership; account and channel configuration; conversation and message removal — with an "all events" default. Group and option labels are i18n copy owned by Konversio.

#### Scenario: filter by a single type

- Given audit entries for inboxes and macros exist
- When the listing is requested with the inbox type filter
- Then only inbox entries are returned

#### Scenario: unknown type values are ignored

- Given the listing is requested with a type value that is not a string
- Then that value does not affect the query and no error is raised

---

### Requirement: actor search

The endpoint SHALL accept an optional search term and return only entries whose recorded username, or whose linked user's name or email, matches the term as a case-insensitive substring. User-record matching applies only to entries whose actor is a user.

#### Scenario: search by email fragment

- Given an entry recorded for "admin@example.com"
- When the listing is searched with "admin@exam"
- Then that entry is included in the results

#### Scenario: search is safe against pattern metacharacters

- Given an entry recorded for "100%_sure@example.com"
- When the listing is searched with the literal text "100%_"
- Then the entry is matched literally, not as a wildcard pattern

#### Scenario: search by linked user name

- Given an entry whose actor is a user named "Jane Agent"
- When the listing is searched with "jane"
- Then that entry is included in the results

---

### Requirement: date window filtering

The endpoint SHALL accept optional `since` and `until` boundaries as unix epoch seconds and return only entries created within that inclusive window. Values outside the range representable by the database, or that cannot be parsed as integers, MUST be ignored rather than rejected.

#### Scenario: window bounds are applied

- Given entries created on three consecutive days
- When the listing is requested with `since` at the start of day two and `until` at the end of day two
- Then only day-two entries are returned

#### Scenario: garbage epoch values are ignored

- Given the listing is requested with `since` set to "not-a-number" and `until` set to a value beyond year 9999
- Then the request succeeds and the date window is not applied

---

### Requirement: chronological sorting

The endpoint SHALL order entries by creation time, newest first by default, and SHALL accept an explicit ascending or descending direction.

#### Scenario: default order is newest first

- Given several audit entries created at different times
- When the listing is requested without a sort parameter
- Then entries are returned in descending creation-time order

#### Scenario: ascending order on request

- Given several audit entries created at different times
- When the listing is requested with ascending sort
- Then entries are returned in ascending creation-time order

---

### Requirement: URL-synchronized UI state

The audit logs settings page SHALL keep its page number, search term, event-type filter, date window, and sort direction in the route query, so filtered views are shareable and survive navigation. The page MUST refetch whenever the query changes.

#### Scenario: filter change resets pagination

- Given the administrator is on page 3 of unfiltered results
- When they select an event-type filter
- Then the route query drops the page parameter and the first page of filtered results loads

#### Scenario: shared URL restores the view

- Given a URL containing a search term, a type filter, a date window, and ascending sort
- When an administrator opens that URL
- Then the page renders with those filters applied and the matching results

---

### Requirement: debounced search input

The page's search field SHALL commit the typed term to the route query only after a short debounce and only when the term is at least three characters long (an emptied field clears the filter). Navigation echoes of the page's own committed term MUST NOT overwrite text the administrator is still typing.

#### Scenario: short terms are not committed

- Given the administrator has typed "ab" in the search field
- When the debounce interval elapses
- Then the route query has no search parameter and results are unfiltered

#### Scenario: typing is not clobbered by the URL watcher

- Given the administrator committed the term "jane" and then continues typing
- When the route updates to reflect "jane"
- Then the search field keeps the administrator's newer in-progress text

---

### Requirement: empty states and clear-filters

The page SHALL distinguish "no audit entries exist in this account" from "no entries match the active filters", and SHALL offer a clear-filters action whenever any filter is active.

#### Scenario: no matches under filters

- Given an account with audit entries but none matching the active filters
- Then the page shows a no-matching-results message, not the no-entries message

#### Scenario: clear filters resets the view

- Given active filters on the page
- When the administrator chooses clear filters
- Then the route query empties, the search field clears, and the unfiltered first page loads
