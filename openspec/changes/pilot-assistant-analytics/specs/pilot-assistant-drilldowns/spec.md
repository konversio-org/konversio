## Capability: pilot-assistant-drilldowns

Administrator-only, paginated listing of the exact conversations behind a supported overview metric, reusing the shared reports drilldown serialization and a drawer UI on the overview page.

---

## ADDED Requirements

### Requirement: Drilldown endpoint with a supported-metric set

The system SHALL expose an authenticated per-assistant drilldown endpoint accepting a metric name, the same `range` and `timezone_offset` inputs the overview used, and pagination parameters. The supported metrics are exactly: conversations involved, auto-resolution rate, handoff rate, and reopen-after-resolution rate. The endpoint MUST resolve the current window through the shared reporting-window service so the drilldown covers precisely the rows its metric counted. Unsupported metric names MUST be rejected with 422.

#### Scenario: unsupported metric is rejected

- Given an administrator requests a drilldown for a metric outside the supported set
- When the endpoint is called
- Then the response is 422 Unprocessable Entity

#### Scenario: window matches the metric card

- Given the overview auto-resolution card for range "30" counted a set of conversations
- When an administrator drills into auto-resolution rate with range "30" and the same timezone offset
- Then the drilldown's total count equals the number the card counted

---

### Requirement: Drilldown cohorts

Drilldown cohorts MUST be defined so they match the overview aggregates: the involved cohort is conversations with at least one AI-authored message in the window; the auto-resolution cohort additionally requires a countable AI resolution event in the window, excluding time-based bot resolutions on conversations that were also handed off; the handoff cohort is involved conversations with a handoff event in the window; the reopen cohort is auto-resolved conversations that reopened at or after their AI resolution, with the reopen falling inside the window. needs investigation: confirm which reporting-event names the Konversio Pilot resolution path emits (`conversation_pilot_inference_resolved` and/or the generic `conversation_bot_resolved`) so the event-based cohorts count rows identical to the episode-based aggregates.

#### Scenario: handed-off conversation resolved by timer is not an auto-resolution

- Given a conversation the AI was involved in, which was handed off and later closed without a human reply, producing a time-based bot resolution event
- When an administrator drills into auto-resolution rate
- Then that conversation is excluded from the list

#### Scenario: reopen list requires an AI resolution first

- Given a conversation that reopened after a purely human resolution
- When an administrator drills into reopen-after-resolution rate
- Then that conversation is excluded from the list

---

### Requirement: Pagination and response meta

The endpoint MUST paginate with a default of 25 records per page (page 1 default) and a hard maximum of 100 per page, and MUST return meta containing the metric name, current page, per-page size, total record count, and the resolved window bounds as epoch seconds. Records MUST be serialized with the shared reports drilldown record serializer so existing drawer components render them unchanged.

#### Scenario: per-page is clamped

- Given an administrator requests 500 records per page
- When the drilldown is built
- Then at most 100 records are returned
- And meta reports the clamped per-page size

#### Scenario: meta describes the window

- Given a drilldown for range "7"
- When the response is rendered
- Then meta contains since/until epoch bounds matching the current window

---

### Requirement: Administrator-only access

The drilldown endpoint MUST be restricted to account administrators, enforced by the assistant policy. The overview page MUST hide the drilldown affordance for non-administrators rather than letting them hit a forbidden response.

#### Scenario: agent cannot drill down

- Given a non-administrator account user
- When they request the drilldown endpoint directly
- Then the response is an authorization failure

#### Scenario: drilldown affordance hidden for agents

- Given a non-administrator views the assistant overview page
- Then metric cards render without any drilldown entry point

---

### Requirement: Drilldown drawer UI

The overview page MUST open a right-side drawer when an administrator activates a supported metric card, listing the conversations behind that metric with loading, empty, and error states, "Load more" pagination, and rows that link into the conversation view.

#### Scenario: load more appends the next page

- Given a drilldown with more records than one page
- When the administrator activates "Load more"
- Then the next page is appended to the list
- And the meta total count remains consistent

#### Scenario: row navigates to the conversation

- Given the drawer lists conversations
- When the administrator activates a row
- Then the application navigates to that conversation
