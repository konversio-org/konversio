## Capability: voice-call-core

The shared call domain: one `Call` record per call across Twilio and WhatsApp providers, a single status state machine, voice-call conversation messages, realtime events, display normalization, a per-call recording snapshot, and call-record preservation across contact merges.

---

## ADDED Requirements

### Requirement: Call record

The system SHALL persist one `Call` record per call with: account, inbox, conversation, optional contact, optional message, optional accepting agent, a provider (`twilio` or `whatsapp`), a direction (`incoming` or `outgoing`), a provider-assigned call identifier, a status, optional `started_at`, `duration_seconds`, `end_reason`, a `transcript`, a `meta` jsonb bag (conference identifiers, recording identifier, parent call identifier, initiated/ended timestamps, accepted-broadcast gate, recording-enabled snapshot), and an attachable audio recording. The pair `(provider, provider_call_id)` MUST be unique.

#### Scenario: provider call id is unique per provider

- Given a call exists with provider `twilio` and provider call id `CA123`
- When another call is created with provider `twilio` and provider call id `CA123`
- Then the create fails with a uniqueness violation

#### Scenario: same call id allowed across providers

- Given a call exists with provider `twilio` and provider call id `abc`
- When a call is created with provider `whatsapp` and provider call id `abc`
- Then the call is created successfully

#### Scenario: active scope excludes terminal calls

- Given calls in statuses `ringing`, `in_progress`, `completed`, and `failed`
- When the active scope is queried
- Then only the `ringing` and `in_progress` calls are returned

---

### Requirement: Call status state machine

Call status MUST be one of `ringing`, `in_progress`, `completed`, `no_answer`, `failed`, `rejected`. The statuses `completed`, `no_answer`, `failed`, and `rejected` are terminal: once a call reaches a terminal status, no further status update SHALL change it. Transitioning to `in_progress` SHALL set `started_at`, keeping the earliest observed timestamp when multiple in-progress updates arrive. Transitioning to a terminal status SHALL record the end timestamp and set `duration_seconds` from the provided duration or, absent one, from elapsed time since `started_at` (never negative). Every applied transition SHALL bump the conversation's `last_activity_at` and touch the call's message so connected clients rebroadcast.

#### Scenario: terminal status cannot be overwritten

- Given a call in status `rejected`
- When a delayed provider update reports `completed`
- Then the call remains `rejected`
- And its end reason is unchanged

#### Scenario: earliest in-progress timestamp wins

- Given a ringing call
- When an in-progress update arrives at time T1 and another at time T2 > T1
- Then `started_at` equals T1

#### Scenario: duration derived from started_at when not provided

- Given a call that moved to `in_progress` at time T
- When a terminal update arrives at time T + 95 seconds without a duration
- Then `duration_seconds` is 95

#### Scenario: repeated same-status updates are ignored

- Given a call in status `in_progress`
- When another `in_progress` update arrives
- Then no attributes change

---

### Requirement: Voice call conversation message

Each call SHALL be represented in its conversation by a message of content type `voice_call` carrying a data payload with the call id, provider call id, provider, display direction, and display status. The message's sender and message type MUST follow the call direction (outgoing calls are authored by the calling agent, incoming calls by the contact). Status updates SHALL patch the message payload with the new status, the accepting agent (id and name) when known, and the duration when known. The call payload MUST be embedded in message serialization so clients render the bubble without a refetch. The conversation SHALL mirror the call's display status in `additional_attributes.call_status`.

#### Scenario: call creation posts a voice_call message

- Given an inbound call is built for a conversation
- Then the conversation contains an incoming `voice_call` message authored by the contact
- And the message data payload contains the call id, provider, direction `inbound`, and status `ringing`
- And the call record references the message

#### Scenario: message and call are linked atomically

- Given an outbound WhatsApp call is initiated
- When the call and its message are created
- Then the message-created broadcast fires only after the call references the message
- And clients never observe a ringing bubble without its call payload

#### Scenario: status update patches the message payload

- Given a call whose message shows status `ringing`
- When the call is accepted by agent "Ada"
- Then the message payload shows status `in-progress` and accepted-by `{id, name}` for Ada
- And the conversation's `call_status` is `in-progress`

---

### Requirement: Realtime call events

The system SHALL broadcast account-wide ActionCable events for call lifecycle transitions — at minimum call created, call accepted, and call ended — with a payload containing the call id, provider call id, provider, conversation id, and account id, plus event-specific extras (accepting agent id, final display status). Twilio and WhatsApp calls MUST emit the same event names and payload shape so clients handle both providers uniformly. The accepted event MUST fire exactly once per call, and only after the accepting agent's media leg is confirmed connected — not when the join request is received. A terminal status MUST be persisted before the ended event is broadcast.

#### Scenario: accepted broadcast fires once

- Given an agent's join is claimed and later the provider confirms the leg joined
- When duplicate join confirmations arrive
- Then exactly one `accepted` event is broadcast for the call

#### Scenario: ended broadcast follows persisted terminal status

- Given an in-progress call
- When the agent hangs up
- Then the call record is terminal before the `ended` event is broadcast
- And no subsequent `accepted` event can be emitted for the call

---

### Requirement: Display normalization

The API SHALL render direction as `inbound`/`outbound` and status in hyphenated form (e.g. `in-progress`, `no-answer`), while storing `incoming`/`outgoing` and underscored statuses. Filter and query inputs MUST accept either form.

#### Scenario: call payload renders display forms

- Given an outgoing call in status `in_progress`
- When the call payload is serialized
- Then `direction` is `outbound` and `status` is `in-progress`

#### Scenario: filters accept display forms

- Given calls exist with status `no_answer`
- When the call history API is queried with status `no-answer`
- Then those calls are returned

---

### Requirement: Recording enablement snapshot

At call creation, the call SHALL snapshot the inbox channel's recording-enabled setting into its own metadata, so all legs of the call agree and a mid-call settings change cannot alter the live call. A call without a snapshot (predating the setting) MUST be treated as recording-enabled.

#### Scenario: snapshot taken at creation

- Given an inbox with recording disabled
- When a call is created on that inbox
- Then the call's recording snapshot is disabled
- And enabling recording on the inbox mid-call does not change the call's snapshot

#### Scenario: legacy call defaults to recorded

- Given a call whose metadata contains no recording snapshot
- Then the call is treated as recording-enabled

---

### Requirement: Call records preserved when contacts merge

When two contacts are merged, all call records pointing at the merged-away contact MUST be re-pointed to the surviving contact within the same merge transaction, so call history and the calls dashboard remain complete. This change specs only the call-record step; the merge flow itself is owned by `companies-management`.

#### Scenario: calls follow the surviving contact

- Given contact A has two calls and contact B has one call
- When contact B is merged into contact A
- Then all three calls belong to contact A
- And each call still references its original conversation and message

#### Scenario: merge rollback keeps calls in place

- Given a merge that fails after the call reassignment step
- When the transaction rolls back
- Then the calls still belong to their original contacts
