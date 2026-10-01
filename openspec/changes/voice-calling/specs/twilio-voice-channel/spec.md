## Capability: twilio-voice-channel

Voice calling on Twilio channels: per-channel voice enablement, inbound and outbound calls bridged through named conferences, browser agent join with first-join-wins claim, mute and inbound-call controls, provider-side recordings, explicit outbound-call errors, and a channel health check.

---

## ADDED Requirements

### Requirement: Voice enablement on Twilio channels

A Twilio channel SHALL carry a `voice_enabled` flag (default off) plus the provider credentials voice requires (TwiML app identifier, API key secret). Enabling voice MUST configure the provider phone number's voice webhook to point at the application; disabling it SHOULD tear that configuration down. Webhook and callback endpoints for a number MUST reject processing when the channel is not voice-enabled.

#### Scenario: enabling voice registers the voice webhook

- Given a Twilio SMS inbox with voice disabled
- When an admin enables voice and supplies valid TwiML app credentials
- Then the channel is marked voice-enabled
- And the provider number's voice webhook points at the application's voice endpoint

#### Scenario: voice webhook on a non-voice number is refused

- Given a Twilio channel with voice disabled
- When a voice webhook payload arrives for that number
- Then the request fails with a not-found error
- And no call, conversation, or message is created

---

### Requirement: Outbound calls from the dashboard

An agent SHALL be able to start an outbound call to a contact's phone number from a voice-enabled Twilio inbox they are assigned to, optionally naming the conversation they are viewing. The system MUST reject the request when the contact has no phone number or the inbox is not voice-enabled. A named conversation is reused only when it belongs to the same inbox and contact and is open; otherwise a new open conversation is created with the calling agent as assignee. A reused conversation that is unassigned SHALL be claimed by the calling agent. The response MUST include the conversation id, the provider call id, and the conference name. The call is created already accepted by the calling agent, in `ringing` status, with its `voice_call` message.

#### Scenario: outbound call from a contact card

- Given a voice-enabled Twilio inbox and a contact with a phone number
- When the agent initiates a call without a conversation hint
- Then a new open conversation is created with the agent as assignee
- And a ringing outgoing call with a `voice_call` message exists
- And the response includes the conversation id, call id, and conference name

#### Scenario: resolved conversation is never reused

- Given the agent views a resolved conversation with the contact
- When the agent initiates a call naming that conversation
- Then a new open conversation is created instead
- And the call bubble appears in the new conversation

#### Scenario: contact without phone number is rejected

- Given a contact with no phone number
- When an agent initiates a call
- Then the request fails with a validation error
- And no call or conversation is created

---

### Requirement: Inbound Twilio calls

When a call arrives on a voice-enabled number, the voice webhook SHALL resolve the inbox by phone number and build the call idempotently: resolve the contact through the shared multi-identity resolution, reuse the latest non-resolved conversation on the resolved contact-inbox (the single locked conversation on locked inboxes) or open a new one, create a ringing incoming call, and post its `voice_call` message. Provider retries of the same webhook MUST NOT duplicate the call. When the inbox has inbound calls disabled, the webhook MUST answer with provider rejection markup and create nothing. The webhook response MUST be conference-bridging markup that honors the call's recording snapshot and labels agent and contact participants distinctly.

#### Scenario: inbound call rings the inbox

- Given a voice-enabled Twilio inbox with inbound calls enabled
- When the provider posts a voice webhook for an incoming call from `+15551234567`
- Then a contact for that number, an open conversation, a ringing incoming call, and a `voice_call` message exist
- And the webhook response bridges the caller into the call's conference

#### Scenario: webhook retry is idempotent

- Given an inbound call already built for provider call id `CA123`
- When the same voice webhook arrives again
- Then the existing call is used
- And no duplicate call, conversation, or message is created

#### Scenario: inbound calls disabled rejects the caller

- Given a voice-enabled inbox with inbound calls disabled
- When a voice webhook arrives for a contact-initiated call
- Then the response rejects the call at the provider
- And no call, conversation, or message is created

---

### Requirement: Conference join, claim, and lifecycle

Agents SHALL join a call from the browser using a short-lived provider access token scoped to the user and inbox. Joining a call claims it for the first agent to join: the accepting agent is recorded under a row lock, an unassigned conversation is auto-assigned to that agent, and the call transitions to `in_progress` once the provider confirms the agent leg joined. A join attempt for a call already claimed by another agent MUST fail with a conflict naming the accepting agent. Provider conference events drive transitions: join (agent) → in_progress; leave while ringing → no_answer; leave while in_progress → completed; conference end → completed for any non-terminal call. Events referencing another account's agent label MUST be ignored. Terminal calls MUST ignore all further events.

#### Scenario: first agent to join wins

- Given a ringing inbound call
- When agent Ada joins the conference
- Then the call is accepted by Ada and transitions to `in_progress`
- And the conversation is assigned to Ada if it was unassigned

#### Scenario: second join is refused with conflict

- Given a call accepted by Ada
- When agent Ben attempts to join
- Then the request fails with a 409 conflict naming Ada
- And the call remains accepted by Ada

#### Scenario: caller hangs up while ringing

- Given a ringing inbound call with no agent joined
- When the contact leg leaves the conference
- Then the call transitions to `no_answer`

#### Scenario: spoofed cross-account agent label is ignored

- Given a conference join event whose agent label embeds a different account id
- When the event is processed
- Then no agent is attached to the call

---

### Requirement: Leave or end a call

An agent SHALL be able to leave a call. The provider conference MUST be torn down first; only then is the call finalized under a row lock: a ringing call with no accepting agent becomes `rejected` (end reason agent-rejected, recorded against the leaving agent), an in-progress call becomes `completed` (end reason agent-hangup), any other non-terminal call becomes `no_answer` (end reason agent-hangup). The ended broadcast fires only after the terminal status is persisted. If provider teardown fails, local state MUST be left untouched so the call remains repairable.

#### Scenario: agent leaves a ringing outbound call

- Given a ringing call with no accepting agent
- When the agent leaves
- Then the call is `rejected` with end reason agent-rejected

#### Scenario: agent hangs up mid-call

- Given an in-progress call accepted by the agent
- When the agent leaves
- Then the provider conference is ended
- And the call is `completed` with end reason agent-hangup and a computed duration

---

### Requirement: Mute controls

During an active Twilio call, the agent SHALL be able to mute and unmute their own microphone from the call UI without affecting other participants or the call status.

#### Scenario: toggling mute during a call

- Given an in-progress call in the browser
- When the agent activates mute
- Then the agent's audio is no longer transmitted
- And the call status remains `in_progress`
- And deactivating mute restores audio

---

### Requirement: Inbound calls toggle

A voice-enabled Twilio inbox SHALL expose an inbound-calls setting (default on) that mutes only the incoming side of calling: when off, fresh contact-initiated calls are rejected at the provider while outbound calling and in-progress calls are unaffected.

#### Scenario: outbound still works with inbound disabled

- Given a voice-enabled inbox with inbound calls disabled
- When an agent places an outbound call
- Then the call proceeds normally

---

### Requirement: Call recordings

When a call's recording snapshot is enabled, the provider conference SHALL record from the start. On the provider's completed-recording callback, the system SHALL enqueue a background job that downloads the recording with the channel credentials (audio content types only, fetched through the SSRF-safe fetcher) and attaches it to the call idempotently. The attachment SHALL set `duration_seconds` from the recording duration when the call has none, and touch the call's message so clients rebroadcast with the recording URL. The serialized call payload MUST expose a playable recording URL when attached, and an inbox settings page MUST let admins review and replay recordings from the conversation bubble and the calls page.

#### Scenario: completed recording is attached once

- Given a completed call with recording enabled
- When the recording callback arrives twice
- Then exactly one recording is attached
- And the call payload exposes a recording URL

#### Scenario: recording callback for a do-not-record call is ignored

- Given a call whose recording snapshot is disabled
- When a recording callback arrives for it
- Then no recording is attached

---

### Requirement: Clear outbound call errors

Outbound call failures MUST surface as distinct, user-meaningful errors rather than generic failures: contact has no phone number, calling is not enabled on the inbox, the call was already accepted by another agent, the call already ended, the call is not in a state that allows the action, and provider call failure.

#### Scenario: distinct error for a dead call

- Given a call that already ended
- When an agent attempts to accept it
- Then the API responds with an already-ended error distinct from the already-accepted error

---

### Requirement: Twilio channel health check

The system SHALL provide a health check for a Twilio channel that reports: each expected webhook and whether the provider has it configured with the correct URL and method (for both messaging-service and direct number configurations), the provider account status, the sender details and capabilities (voice capability required when voice is enabled), whether voice is enabled, and an overall `healthy`/`misconfigured` verdict. A provider account that cannot be read due to restricted credentials MUST be reported as unknown rather than unhealthy; credential or lookup failures MUST surface as request errors.

#### Scenario: correctly configured voice number is healthy

- Given a voice-enabled channel whose provider webhooks match the expected URLs and whose number has voice capability
- When the health check runs
- Then the verdict is `healthy`

#### Scenario: wrong webhook method is misconfigured

- Given a channel whose provider voice webhook points at the right URL with the wrong HTTP method
- When the health check runs
- Then the verdict is `misconfigured`
- And the offending webhook is listed as not configured

#### Scenario: restricted API key does not fail the verdict

- Given credentials that may read numbers but not the account resource
- When the health check runs
- Then the account section is reported as absent context
- And the verdict reflects webhooks and capabilities only
