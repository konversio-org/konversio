## Capability: pilot-conversation-outcomes

Episode-grained recording of Pilot AI involvement per conversation. Each conversation carries an ordered stream of outcome episodes — half-open windows of potential AI involvement — persisting lifecycle timestamps, reply facts, categorized handoffs, resolutions, reopen episodes, and CSAT ratings.

---

## ADDED Requirements

### Requirement: Episode data model

The system SHALL persist outcome episodes in a `pilot_conversation_outcomes` table, one row per episode, keyed to the account, the conversation, the inbox, and the Pilot assistant the episode is attributed to. Each episode SHALL record: what triggered its opening, its start timestamp, its end timestamp (empty while the episode is open), AI reply facts (count of public AI replies, first and last AI reply timestamps), first human reply timestamp, handoff timestamp with a categorized reason, resolution timestamp, and CSAT rating with receipt timestamp.

#### Scenario: episode belongs to one account's records

- Given an episode is created
- Then it references the conversation's account, the conversation, the conversation's inbox, and a `Pilot::Assistant`
- And the record is invalid if the assistant, conversation, or inbox belongs to a different account

#### Scenario: at most one open episode per conversation

- Given a conversation has an episode with no end timestamp
- When a second episode without an end timestamp is inserted for the same conversation
- Then the database rejects it

#### Scenario: at most one initial episode per conversation

- Given a conversation already has an episode marked as its first-triggered episode
- When another first-triggered episode is inserted for the same conversation
- Then the database rejects it

---

### Requirement: Initial episode on first Pilot eligibility

When Pilot first becomes eligible to respond on a conversation (an incoming message arrives on an inbox with an attached, active Pilot assistant on an account with the Pilot feature enabled), the system SHALL open that conversation's first episode at the triggering message's timestamp. Opening the first episode SHALL be idempotent.

#### Scenario: first eligible message opens the initial episode

- Given a conversation on an inbox with an attached Pilot assistant and no existing episodes
- When an incoming customer message arrives that Pilot is eligible to answer
- Then an episode marked as the conversation's first is created, starting at the message's creation time

#### Scenario: eligibility recording is idempotent

- Given the conversation's first episode already exists
- When Pilot eligibility is recorded again for a later message
- Then no additional first-triggered episode is created

#### Scenario: inbox without an attached assistant records nothing

- Given a conversation on an inbox with no attached Pilot assistant
- When an incoming customer message arrives
- Then no episode is created

---

### Requirement: Reopen opens a new episode

When a conversation transitions away from the resolved status and at least one episode exists for it, the system SHALL close the currently open episode at the transition timestamp and open a new episode starting at that same timestamp, marked as reopen-triggered. The new episode SHALL be attributed to the assistant currently attached to the inbox when one is attached, otherwise to the assistant of the episode being closed. When no episode exists for the conversation, a reopen SHALL record nothing.

#### Scenario: reopen closes and succeeds the open episode

- Given a resolved conversation whose open episode was previously recorded
- When the conversation is reopened at time T
- Then the previous episode's end timestamp is set to T
- And a new reopen-triggered episode starts at T

#### Scenario: new episode follows the currently attached assistant

- Given the closed episode was attributed to assistant A
- And the inbox now has assistant B attached
- When the conversation is reopened
- Then the new episode is attributed to assistant B

#### Scenario: reopen with no episode history is a no-op

- Given a conversation with no episodes
- When the conversation is reopened
- Then no episode is created

---

### Requirement: Handoff recording with categorized reason

When a Pilot conversation is handed off to humans, the system SHALL record the handoff timestamp and a categorized reason on the episode covering that time. The reason taxonomy SHALL be owned by the model, be extensible, and MUST include a category denoting transfers caused by exhaustion of AI usage quota. needs investigation: Konversio's final category set (see design Decisions).

#### Scenario: handoff lands on the covering episode

- Given an open episode covering time T
- When a handoff is recorded at time T with a reason category
- Then that episode carries the handoff timestamp T and the reason category

#### Scenario: handoff with no covering episode is a no-op

- Given no episode covers time T
- When a handoff is recorded at time T
- Then no episode is modified and no error is raised

#### Scenario: quota-driven transfers are distinguishable

- Given a conversation handed off because the AI usage quota was exhausted before the AI replied
- When the handoff is recorded
- Then its reason category identifies it as a quota-driven transfer, distinct from genuine escalation categories

---

### Requirement: Resolution recording

When a conversation is resolved, the system SHALL record the resolution timestamp on the episode covering that time.

#### Scenario: resolution lands on the covering episode

- Given an open episode covering time T
- When the conversation is resolved at time T
- Then that episode carries the resolution timestamp T

---

### Requirement: AI reply facts snapshot at terminal events

When a handoff or resolution is recorded on an episode, the system SHALL recompute that episode's AI reply facts from the conversation's messages within the episode window: the count of public, non-private outgoing messages authored by the Pilot assistant, and the first and last such message timestamps. Facts for episodes with no AI replies SHALL remain at their zero/empty defaults.

#### Scenario: snapshot reflects the episode window only

- Given an episode spanning [T1, T2)
- And AI replies at T0 (before T1), T1.5, and T2.5 (after T2)
- When the episode's facts are snapshotted
- Then the reply count is 1 and first and last reply timestamps are both T1.5

#### Scenario: later AI replies update the snapshot

- Given an episode whose facts were snapshotted at handoff time
- When a resolution is recorded later and further AI replies occurred in between
- Then the snapshot is recomputed to include the intervening replies

---

### Requirement: First human reply attribution

The system SHALL record the timestamp of the first qualifying human reply on the episode covering that message's creation time. A message qualifies only if it is a public, outgoing, non-private message authored by a human agent, or a human reply echoed back from an external channel. Messages generated by automation rules and campaign outreach MUST NOT qualify. Attribution SHALL be idempotent per episode.

#### Scenario: first human reply is recorded once

- Given an open episode with no human reply recorded
- When a qualifying human reply is created at time T
- Then the episode's first human reply timestamp is T
- And a later qualifying human reply does not change it

#### Scenario: automation and campaign messages do not qualify

- Given an open episode with no human reply recorded
- When an outgoing message generated by an automation rule, then a campaign message, are created
- Then the episode's first human reply timestamp remains empty

#### Scenario: external echo of a human reply qualifies

- Given an open episode with no human reply recorded
- When a human reply sent via an external channel is echoed into the conversation
- Then the episode's first human reply timestamp is set to the echoed message's creation time

---

### Requirement: CSAT attribution

When a CSAT survey response is received for a conversation, the system SHALL record the rating and the response receipt timestamp on the episode whose window covers the survey message's creation time. Responses not covered by any episode SHALL record nothing.

#### Scenario: rating lands on the covering episode

- Given an episode whose window covers the CSAT survey message's creation time
- When the customer submits a rating
- Then that episode carries the rating value and the receipt timestamp

#### Scenario: uncovered response records nothing

- Given a conversation whose episodes all ended before the survey message's creation time
- When the customer submits a rating
- Then no episode is modified

---

### Requirement: Failure isolation

All episode recording SHALL be failure-isolated: any error during recording MUST be logged and reported to the exception tracker, and MUST NOT propagate into the message, handoff, resolution, or survey flows that triggered it.

#### Scenario: a recording failure does not break resolution

- Given episode recording will raise an error
- When a conversation is resolved
- Then the resolution completes normally
- And the error is logged and reported to the exception tracker

---

### Requirement: Tracking-start watermark

The system SHALL expose the timestamp at which outcome recording began, defined as the creation time of the earliest episode, cached so repeated lookups do not query the table. When no episodes exist the watermark SHALL be empty.

#### Scenario: watermark reflects the earliest episode

- Given episodes created at times T1 < T2 < T3
- When the tracking-start watermark is read
- Then it returns T1

#### Scenario: watermark is empty before any recording

- Given no episodes exist
- When the tracking-start watermark is read
- Then it is empty
