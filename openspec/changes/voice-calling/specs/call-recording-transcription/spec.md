## Capability: call-recording-transcription

Per-inbox call recording and transcription settings, and transcription of completed call recordings through Pilot speech-to-text. This capability is a clean-room re-expression of an upstream Enterprise feature: requirements are stated functionally, target Konversio's core tree and `Pilot::` naming, and no upstream implementation identifiers apply.

---

## ADDED Requirements

### Requirement: Per-inbox call recording setting

Every channel type that can place calls SHALL expose a recording setting, stored in the channel's provider configuration and defaulting to on. Inboxes created before the setting existed MUST behave as recording-enabled. The setting SHALL be readable and writable through the inbox API and editable from the inbox settings UI. The value in force at call creation is snapshotted onto the call (see `voice-call-core`); changing the setting never affects calls already created.

#### Scenario: default is on for existing inboxes

- Given an inbox whose channel predates the recording setting
- Then the channel reports recording enabled
- And new calls on it are recorded

#### Scenario: disabling recording stops new recordings

- Given an admin turns recording off for an inbox
- When a new call is placed and completed on that inbox
- Then no recording is captured or stored for that call

#### Scenario: setting round-trips through the inbox API

- Given a voice-capable inbox
- When the inbox is updated with recording disabled
- Then the inbox API response reflects the disabled setting
- And the inbox settings UI shows it off

---

### Requirement: Per-inbox call transcription setting

Every channel type that can place calls SHALL expose a transcription setting, stored in the channel's provider configuration and defaulting to on, editable alongside the recording setting. Transcription only applies where a recording exists; disabling recording implicitly disables transcription for those calls regardless of the transcription setting.

#### Scenario: transcription off with recording on

- Given an inbox with recording on and transcription off
- When a recorded call completes
- Then the recording is stored
- And no transcript is produced

---

### Requirement: Transcription of call recordings

After a recording is attached to a call, and only for the attachment attempt that actually persisted the audio, the system SHALL enqueue a low-priority background job that transcribes the recording when all of the following hold: the call has no transcript yet, the inbox's transcription setting is on, a Pilot speech-to-text capability is configured and available for the account, and the audio is within the speech-to-text provider's documented size limit (oversized audio keeps the recording but skips transcription). On success the transcript MUST be stored on the call record. needs investigation: the Pilot speech-to-text provider configuration, model routing, and usage accounting do not exist yet in Konversio and must be defined against Pilot's existing LLM configuration.

#### Scenario: recorded call is transcribed

- Given a completed call with an attached recording on a transcription-enabled inbox with Pilot speech-to-text available
- When the transcription job runs
- Then the call's transcript contains the spoken content
- And the transcript appears on the call bubble and the calls page

#### Scenario: oversized recording is skipped

- Given a recording larger than the provider's documented size limit
- When the transcription job runs
- Then no transcript is produced and the recording remains available

#### Scenario: transcription setting off skips the work

- Given an inbox with transcription disabled
- When a recording is attached
- Then no transcription job performs provider work

---

### Requirement: Transcription job resilience

The transcription job MUST split producing the transcript from publishing it, so a publishing failure can retry without re-running (and re-charging) the transcription. Transient storage failures (audio blob temporarily unavailable) MAY be retried a small number of times with a short delay. Provider errors that can never succeed for this audio (for example the provider rejecting the audio as corrupt or refusing the configured credentials) MUST NOT be retried. Publishing MUST reindex the call's message when advanced search is enabled and then rebroadcast the message so connected clients receive the embedded call payload with the transcript; reindexing MUST happen before the broadcast so a retry cannot send duplicate client updates.

#### Scenario: publish failure retries without re-transcribing

- Given transcription succeeded and stored the transcript, but the publish step failed
- When the job retries
- Then the provider is not invoked again
- And only the publish step runs

#### Scenario: permanently bad audio is not retried

- Given the provider rejects the recording as unusable audio
- When the job fails with that error
- Then the job is discarded rather than retried
