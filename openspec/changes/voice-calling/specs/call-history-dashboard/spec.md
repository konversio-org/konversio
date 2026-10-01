## Capability: call-history-dashboard

An account-scoped call history API and a Calls page in the dashboard: role-based visibility, status/direction/inbox/agent/date filters, pagination, and per-row call details including recording playback and transcript.

---

## ADDED Requirements

### Requirement: Call history API

The system SHALL expose an account-scoped call index endpoint returning calls newest-first, paginated at 25 per page, with the total count. Each row MUST include the call's display status and direction, duration, end reason, timestamps, from/to numbers, contact, conversation id, accepting agent (id and name), inbox, recording URL when present, and transcript when present. Contact, conversation, agent, and inbox data MUST be eager-loaded so listing does not issue per-row queries.

#### Scenario: calls are listed newest first with count

- Given 30 calls in the account
- When page 1 is requested
- Then 25 calls are returned in reverse chronological order with a total count of 30

#### Scenario: row includes playback and transcript data

- Given a completed call with a recording and a transcript
- When the call history is listed
- Then the row includes a playable recording URL and the transcript text

---

### Requirement: Role-based visibility

Administrators and users holding the report-manage permission SHALL see all calls in the account. Every other user SHALL see only calls they personally accepted, and only within conversations they can currently access through the standard conversation permission filtering.

#### Scenario: admin sees all calls

- Given calls accepted by several agents
- When an administrator lists calls
- Then all of them are returned

#### Scenario: agent sees only own handled calls in accessible conversations

- Given agent Ada accepted a call in a conversation she can access, agent Ben accepted another call, and Ada accepted a call in a conversation she can no longer access
- When Ada lists calls
- Then only her accessible accepted call is returned

---

### Requirement: Filters

The index SHALL support filtering by status, direction, inbox, accepting agent, and a creation date range given as unix `since`/`until` timestamps. Status and direction filters MUST accept both display forms (`in-progress`, `inbound`) and stored forms (`in_progress`, `incoming`). Filters MUST compose.

#### Scenario: filter by missed inbound calls

- Given completed, no-answer inbound, and no-answer outbound calls
- When filtering by status `no-answer` and direction `inbound`
- Then only the missed inbound calls are returned

#### Scenario: date range filter

- Given calls created on three different days
- When filtering with since/until covering only the middle day
- Then only that day's calls are returned

---

### Requirement: Calls page

The dashboard SHALL provide a Calls page (available to all conversation users) listing call history with a filter bar offering quick filters (missed, no-reply, incoming, outgoing, in-progress) mapped to the API's status/direction parameters, plus inbox, agent, and date-range selection. Each row MUST present a single derived call kind — ongoing, incoming, outgoing, missed (inbound no-answer), no-reply (outbound no-answer), or failed — computed from status and direction, with a status badge, contact, agent, duration, and time. Rows with recordings MUST offer inline playback; rows with transcripts MUST expose the transcript. An empty state MUST be shown when no calls match.

#### Scenario: missed call kind derivation

- Given an inbound call with status `no-answer`
- When the row renders
- Then it is presented as a missed call

#### Scenario: quick filter composes with the API

- Given the user selects the missed filter
- When the list refreshes
- Then the API is queried with status `no-answer` and direction `inbound`

#### Scenario: recording playback from a row

- Given a call with an attached recording
- When the user expands the row
- Then an audio player plays the recording
