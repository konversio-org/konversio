## Capability: report-drilldowns

Administrator-facing drilldown from report bar charts into the underlying conversation and message records, backed by a dedicated paginated, throttled v2 API and a drawer UI on report charts.

Reference implementation: upstream Chatwoot v4.16.0 core tree (MIT) — `app/builders/v2/reports/drilldown_builder.rb`, `drilldown_record_serializer.rb`, `app/services/reports/report_metric_registry.rb`, `drilldown_timestamp_validator.rb`, `Api::V2::Accounts::ReportsController#drilldown`, and the reports drawer frontend (PRs #14626, #14919). Verbatim porting is permitted.

---

## ADDED Requirements

### Requirement: drilldown API endpoint

The system SHALL expose `GET /api/v2/accounts/:account_id/reports/drilldown` returning the records behind one chart bar, scoped to the current account.

#### Scenario: administrator receives a paginated envelope

- Given an administrator requests the drilldown with a supported metric, a bucket timestamp, a valid `since`/`until` range, and a supported dimension type
- When the request is processed
- Then the response is `{ meta, payload }`
- And `meta` includes the metric, record type, resolved bucket bounds as unix timestamps, `current_page`, `per_page`, `total_count`, and `conversation_count`
- And `payload` contains at most `per_page` records for the requested page

#### Scenario: non-administrator is rejected

- Given a user whose account role is not administrator
- When they request the drilldown endpoint
- Then the response is 401 Unauthorized

#### Scenario: invalid parameters are rejected

- Given any of: an unsupported metric name, an unsupported dimension type, non-integer timestamps, `since >= until`, or a bucket that does not overlap the requested range
- When the drilldown endpoint is requested
- Then the response is 422 Unprocessable Entity

#### Scenario: the endpoint is rate limited per user and account

- Given a user exceeds the drilldown throttle for an account (default 10 requests per minute, configurable via environment)
- When they make another drilldown request
- Then the request is throttled independently of the general reports API limit

---

### Requirement: bucket resolution

The drilldown SHALL compute the effective record window as the intersection of the clicked bucket's window with the requested date range, evaluated in the timezone derived from the request's timezone offset.

#### Scenario: full bucket inside the range

- Given a request with `group_by=day`, a bucket timestamp at the start of a day, and a `since`/`until` range spanning many days
- When records are resolved
- Then the effective window is exactly that day in the request timezone

#### Scenario: edge bucket clipped to the range

- Given the first (or last) bar of a chart whose bucket extends before `since` (or after `until`)
- When records are resolved for that bar
- Then the effective window is clipped to `[max(bucket_start, since), min(bucket_end, until))`
- And the records match what the chart counted for that bar

#### Scenario: unsupported group_by falls back to day

- Given a request with a `group_by` outside hour/day/week/month/year
- When the bucket window is computed
- Then a day-sized bucket is used

---

### Requirement: metric-to-record-source mapping

The drilldown SHALL resolve records from the same source the chart aggregate uses, for every public report metric, so that drilldown totals match the bar value.

#### Scenario: conversations count returns conversations

- Given the `conversations_count` metric
- When a bar is drilled into
- Then the payload contains conversations created within the bucket, newest first
- And `record_type` is `conversation`

#### Scenario: message count metrics return messages

- Given the `incoming_messages_count` or `outgoing_messages_count` metric
- When a bar is drilled into
- Then the payload contains messages of that direction created within the bucket, newest first
- And `record_type` is `message`

#### Scenario: event-backed metrics return reporting events

- Given `resolutions_count` or `avg_resolution_time` (resolution events), `avg_first_response_time` (first-response events), or `reply_time` (reply-time events)
- When a bar is drilled into
- Then the payload contains the reporting events of that kind created within the bucket, newest first
- And `record_type` is `conversation`, except `avg_first_response_time` and `reply_time`, whose `record_type` is `message`

#### Scenario: bot resolutions exclude handed-off conversations

- Given the `bot_resolutions_count` metric and a conversation that has both a bot-resolution event and a bot-handoff event within the requested range
- When a bar is drilled into
- Then that conversation's bot-resolution event is excluded
- And the total matches the bot-resolutions chart aggregate

#### Scenario: bot handoffs counted once per conversation

- Given the `bot_handoffs_count` metric and a conversation with multiple bot-handoff events in the bucket
- When a bar is drilled into
- Then at most one record per distinct conversation is returned (the latest such event)
- And the total matches the bot-handoffs chart aggregate

#### Scenario: dimension scoping

- Given a drilldown for a specific inbox, agent, label, or team (dimension type plus record id)
- When records are resolved
- Then only records belonging to that dimension and the current account are returned

---

### Requirement: record serialization

Each payload record SHALL carry enough context to render a compact card and to deep-link into the conversation view without additional requests.

#### Scenario: conversation context on every record

- Given any payload record
- Then it includes the conversation's id and display id, contact name, inbox name, assignee name, status, creation and last-activity timestamps, and a preview of the latest non-activity message when one exists
- And missing contact, inbox, or assignee names are represented as null so the UI can render fallbacks

#### Scenario: message metrics include message content

- Given a record from a message-count metric
- Then it includes the message id, content, message type, sender name, and creation timestamp
- And `occurred_at` equals the message creation time

#### Scenario: event metrics include the metric value

- Given a record from an event-backed metric
- Then `metric_value` is the event's value, or its business-hours value when the request asked for business hours
- And `occurred_at` is the event's end time (falling back to its creation time)
- And conversation rows backed by an event include the event name

#### Scenario: first-response and reply-time rows surface the causative message

- Given a first-response or reply-time event whose conversation has an outgoing or template message created within one second of the event's end time
- When the record is serialized
- Then it is rendered as a message row for that message
- And for first-response events attributed to a user, only a message sent by that user qualifies; otherwise the row falls back to a conversation row

#### Scenario: no N+1 queries for previews

- Given a full page of records
- When the page is serialized
- Then latest-message previews are loaded in a single batch query for the page

---

### Requirement: drilldown drawer on report charts

Report bar charts rendered through the shared report container SHALL let administrators open a right-side drawer of the records behind a bar.

#### Scenario: clicking a non-zero bar opens the drawer

- Given an administrator viewing a report bar chart with at least one non-zero bar
- When they click a non-zero bar
- Then a right-side drawer opens titled with the metric name
- And it shows the bucket label, the bar's value, and the matching record count
- And the drawer is positioned correctly in both LTR and RTL layouts

#### Scenario: zero-value bars are not clickable

- Given a bar whose value is zero
- When the administrator clicks it
- Then no drawer opens

#### Scenario: non-administrators cannot drill down

- Given a user whose account role is not administrator
- When they interact with a report chart
- Then bar clicking is not activated and an "only administrators can drill down" message is shown

#### Scenario: record rows deep-link to conversations

- Given the drawer is open with records
- When the user clicks a row
- Then the app navigates to that conversation
- And message rows additionally target the specific message so the conversation view scrolls to it

#### Scenario: load more pages records in place

- Given the bucket has more records than one page
- When the user activates "Load more"
- Then the next page is appended to the list
- And the action disappears once all records are loaded

#### Scenario: previous and next bar navigation skips empty buckets

- Given the drawer is open for a bar
- When the user activates previous or next bar
- Then the drawer reloads for the nearest bar in that direction whose value is non-zero
- And the buttons are disabled when no such bar exists

#### Scenario: stale responses never overwrite newer requests

- Given the user clicks several bars in quick succession or pages while a request is in flight
- When an earlier request resolves after a newer one
- Then its results are discarded and the drawer reflects only the latest request
- And superseded requests are aborted where the transport supports it

#### Scenario: loading, empty, and error states

- Given the drawer is open
- Then it shows a loading indicator while fetching, a "no records found" message for an empty result, and a "could not load records" message with preserved state on failure
