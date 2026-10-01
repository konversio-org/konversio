## Capability: whatsapp-cloud-calling

WhatsApp Cloud Calling: browser↔Meta WebRTC voice calls on WhatsApp Cloud API inboxes (embedded or manually configured), with an SDP relay through the application, a throttled call-permission opt-in flow, browser-captured recording upload, and WhatsApp-compatible voice notes from the reply box.

---

## ADDED Requirements

### Requirement: WhatsApp calling enablement

A WhatsApp channel using the Cloud API provider SHALL support calling regardless of whether the inbox was created via embedded signup or manual configuration; channels on other providers MUST NOT expose calling. Enabling calling MUST turn calling on at the provider and re-register the webhook subscription to include call events, persisting the local enabled flag only after registration succeeds. Disabling calling MUST unset the local flag and re-register webhooks without call events (best-effort). Calling MUST also respect the account-level voice feature flag.

#### Scenario: manually configured inbox can enable calling

- Given a WhatsApp Cloud inbox created with manual credentials (non-embedded signup)
- When an admin enables calling
- Then calling is enabled at the provider, webhooks include call events, and the inbox accepts calls

#### Scenario: non-Cloud provider cannot enable calling

- Given a WhatsApp inbox on a non-Cloud provider
- When an admin attempts to enable calling
- Then the request is refused

#### Scenario: webhook registration failure leaves the flag off

- Given calling is being enabled and the webhook re-registration fails
- Then the inbox does not report calling enabled

---

### Requirement: Outbound WhatsApp call initiation

An agent SHALL initiate a call from a conversation context or from a contact plus inbox context. Initiation MUST require an SDP offer from the browser, a contact phone number, and a calling-enabled inbox, and MUST authorize the agent on the conversation the call will land in before dialing. The conversation is resolved before dialing (reusing the latest visible non-resolved thread, or the single locked thread on locked inboxes), but the call and its `voice_call` message are created only after the provider accepts the dial, atomically, so a failed dial leaves no empty thread. The response MUST return the call with its provider identifiers so the browser can complete the WebRTC setup.

#### Scenario: initiate from an open conversation

- Given a calling-enabled WhatsApp inbox and an open conversation
- When the agent initiates a call with a valid SDP offer
- Then a ringing outgoing call and its message are created in that conversation
- And the provider has been asked to ring the contact

#### Scenario: missing SDP offer is rejected

- Given a calling-enabled inbox
- When initiation is attempted without an SDP offer
- Then the request fails with a validation error and nothing is dialed

#### Scenario: failed dial leaves no thread

- Given a contact with no existing conversation
- When the provider rejects the dial
- Then no conversation, call, or message is created

---

### Requirement: Inbound WhatsApp calls

Call events in the WhatsApp webhook SHALL be processed only for calling-enabled inboxes. An inbound connect event carrying an SDP offer MUST build the inbound call (contact resolution, conversation reuse, ringing call, `voice_call` message) through the same inbound builder semantics as other providers; when inbound calls are disabled the system MUST reject the call at the provider. A terminate event arriving before its paired connect MUST be tombstoned briefly so the imminent connect does not create a phantom ringing call. A connect event with no matching local call that is not an inbound offer MUST be ignored (it is the provider racing our own outbound call creation). Duplicate inbound connects MUST be ignored. Provider status updates of type call SHALL transition an outbound call to `in_progress` when the contact actually answers, broadcasting an outbound-accepted event.

#### Scenario: inbound WhatsApp call rings the inbox

- Given a calling-enabled inbox with inbound calls enabled
- When a connect event with an SDP offer arrives
- Then a ringing incoming call with its message exists
- And agents see an incoming-call prompt

#### Scenario: terminate before connect is tombstoned

- Given a terminate event for an unknown call id
- When the paired connect arrives within the tombstone window
- Then no call is created

#### Scenario: contact answering an outbound call marks it in progress

- Given a ringing outbound WhatsApp call
- When a provider status update reports the call accepted with a timestamp
- Then the call transitions to `in_progress` with that pickup time
- And an outbound-accepted event is broadcast

---

### Requirement: Call actions and state guards

Agents SHALL be able to accept, reject, and terminate WhatsApp calls. Accept requires the browser's SDP answer, forwards it to the provider, transitions the call to `in_progress`, records the accepting agent, claims the conversation if unassigned, sets the conversation call status, and broadcasts the accepted event — all serialized under the call row lock. Accept on a non-ringing call MUST raise a distinct error for each case: already accepted by another agent, already ended, or otherwise not ringing. Reject MUST invoke the provider reject and finalize the call `rejected` (end reason agent-rejected) unless the call is already in progress or terminal. Terminate MUST invoke the provider terminate; an in-progress call becomes `completed` with locally computed duration, a ringing call becomes `no_answer` (both end reason agent-hangup); terminal calls are left untouched. A provider API failure during any action MUST abort the local transition so a still-live call is never marked ended.

#### Scenario: accept a ringing inbound call

- Given a ringing inbound WhatsApp call
- When an agent accepts with an SDP answer
- Then the answer is forwarded to the provider
- And the call is `in_progress`, accepted by that agent, with the conversation claimed and the accepted event broadcast

#### Scenario: two agents race to accept

- Given a ringing inbound call
- When two agents accept concurrently
- Then exactly one succeeds and the other receives an already-accepted error

#### Scenario: agent hangs up before the contact answers

- Given a ringing outbound call
- When the agent terminates
- Then the call is `no_answer` with end reason agent-hangup

#### Scenario: provider failure aborts the transition

- Given a ringing inbound call and a provider accept call that fails
- When the agent accepts
- Then an error is raised and the call remains `ringing`

---

### Requirement: Call permission flow

When an outbound dial fails because the contact has not granted call permission, the system SHALL send the contact a permission-request message instead of surfacing a raw failure. Repeat requests on the same conversation MUST be throttled so at most one request is sent per 5-minute window. The request MAY use a per-inbox custom body stored in the channel provider config; otherwise a default localized body is used. Sending a request MUST record the outbound request message id on the conversation and post an activity note. When the contact replies affirmatively to that request, the reply MUST be matched back to the recorded request and treated as permission granted, after which dials proceed. The initiate API MUST render the permission-pending state distinctly so the UI can explain why the call did not dial.

#### Scenario: first dial to a contact without permission

- Given a contact who has never granted call permission
- When an agent initiates a call
- Then the provider dial is refused for missing permission
- And the contact receives a permission-request message
- And the conversation shows a permission-requested activity note
- And the API response tells the agent permission was requested

#### Scenario: repeat dial within the throttle window

- Given a permission request was sent 2 minutes ago on the conversation
- When the agent dials again and the provider refuses again
- Then no second permission request is sent

#### Scenario: contact grants permission by replying

- Given a permission request recorded on the conversation
- When the contact replies affirmatively in context of that request
- Then permission is treated as granted
- And a subsequent dial reaches the contact

---

### Requirement: Browser-captured recording upload

For WhatsApp calls, the browser SHALL capture call audio and upload it after the call ends when the inbox's recording setting allows. The upload endpoint MUST require a recording file, MUST independently re-check the call's recording snapshot server-side (a stale tab may hold an outdated toggle), and MUST attach the recording to the call idempotently under a lock so duplicate uploads store once. The uploaded recording MUST become playable from the call bubble and the calls page like any other recording.

#### Scenario: recording uploads after hangup

- Given a completed WhatsApp call on a recording-enabled inbox
- When the browser uploads the captured audio
- Then the recording is attached and exposed on the call payload

#### Scenario: upload refused when recording disabled

- Given a call whose recording snapshot is disabled
- When a recording upload arrives
- Then the upload is refused and nothing is stored

---

### Requirement: WebRTC session configuration

The browser↔provider media path SHALL be configured with at least one STUN server so the browser can discover its public candidate; the server list MUST be overridable via environment configuration. The dashboard MUST guard against accidental navigation away from an active or incoming call (before-unload prompt) and MUST best-effort signal call termination when the page is unloading.

#### Scenario: default ICE servers are provided

- Given no environment override
- When the client requests call session configuration
- Then at least one STUN server URL is included

---

### Requirement: WhatsApp voice notes

When composing in a WhatsApp inbox, the reply box SHALL record voice notes in a WhatsApp-compatible format (ogg with the opus codec where the browser supports it), converting other recorded formats as needed, and MUST surface recording errors to the composer instead of failing silently. Recorded voice notes SHALL be playable inline in the conversation.

#### Scenario: voice note recorded as ogg/opus

- Given a WhatsApp conversation and a browser that supports ogg/opus recording
- When the agent records and sends a voice note
- Then the attachment is audio/ogg and plays on WhatsApp clients

#### Scenario: recording failure is surfaced

- Given microphone access is denied
- When the agent attempts to record
- Then the composer shows a recording error
