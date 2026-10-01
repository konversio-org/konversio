## Capability: pilot-assistant-reopen-rate-performance

Requirements for computing a Pilot assistant's reopen-after-resolution rate without redundant database queries, and for separating range-dependent overview metrics from range-independent stats.

Clean-room notice: the upstream fix (Chatwoot v4.16.1, "performance fix for report reopen-rate calculations") lives entirely in upstream's enterprise-licensed Captain code. These requirements are expressed independently against Konversio's `Pilot::` namespace (core tree only); no upstream code, naming, or structure is carried over.

Precondition: needs investigation: Konversio does not yet have a Pilot assistant overview surface that reports a reopen-after-resolution rate. These requirements are dormant until that surface exists and SHALL be applied to whatever builder/service computes it.

---

## ADDED Requirements

### Requirement: reopen rate reuses the resolved-conversation total

When a Pilot assistant overview reports the share of assistant-resolved conversations that were later reopened, the calculation SHALL reuse the resolved-conversation count already fetched for the same reporting window instead of querying the database a second time for the denominator.

#### Scenario: denominator is not re-queried

- Given the overview has already computed the number of conversations the assistant resolved in the requested window
- When the reopen-after-resolution rate is calculated
- Then the reopened count is divided by the already-available resolved count
- And no additional query is issued to recompute the resolved total

#### Scenario: rate definition is preserved

- Given a window in which the assistant resolved R conversations and C of those were later reopened
- When the rate is reported
- Then it equals C / R (zero when R is zero and C is zero — see the skip requirement)
- And the reported value matches what the redundant-query version would have produced

---

### Requirement: reopen query is skipped when nothing was resolved

When the assistant resolved no conversations in the requested window, the system SHALL NOT issue the reopened-conversations query at all.

#### Scenario: zero resolutions short-circuits the calculation

- Given a reporting window in which the assistant resolved zero conversations
- When overview metrics are computed
- Then no reopened-conversations query is executed
- And the reopen-after-resolution rate is reported as zero or null without querying

---

### Requirement: range-dependent metrics are served separately from range-independent stats

The Pilot assistant overview SHALL serve range-dependent reporting metrics and range-independent knowledge/FAQ statistics from separate endpoints, so that changing the date range refetches only the metrics.

#### Scenario: range change refetches only metrics

- Given the overview is displayed with knowledge/FAQ statistics already loaded
- When the user changes the reporting date range
- Then only the range-dependent metrics endpoint is requested again
- And the knowledge/FAQ statistics endpoint is not re-requested

#### Scenario: stats load independently of metrics

- Given the overview page loads
- When either the metrics request or the knowledge/FAQ stats request fails
- Then the other still renders
- And each endpoint is authorized for the same audience that may view the assistant overview
