## Why

Konversio's v4.13.0 fork base already carries the `calls` and `channel_voice` tables and the first-generation voice UI (voice-call message bubble, Twilio voice client helper, call store), but the entire calling backend was removed with `enterprise/` — there is no call orchestration, no Twilio voice webhooks, no WhatsApp calling, no recordings, and no call history. Upstream shipped the complete feature set across v4.14.0–v4.18.0, and Konversio has no answer for any of it:

- v4.14.0: voice groundwork (unified call tracking), inbound calls, recordings, call join support.
- v4.14.1: WhatsApp/Twilio Cloud Calling and voice-call UX fixes.
- v4.14.2: WhatsApp voice messages and improved Twilio call controls.
- v4.15.0: calling updates, mute controls, inbox call settings.
- v4.16.0: WhatsApp Calls for non-embedded signup inboxes.
- v4.16.1: voice call dashboard.
- v4.16.2: WhatsApp health monitoring, clearer outbound call errors.
- v4.17.0: transcribe Twilio call recordings (EE upstream).
- v4.17.1: preserved call records when merging contacts.
- v4.18.0: per-inbox call recording and transcription settings (EE upstream).

Without this, agents cannot place or receive calls, recordings and transcripts have nowhere to live, and contact merge silently orphans call history.

## What Changes

- Introduce a core-tree call domain: one `Call` record per call (Twilio or WhatsApp), a `ringing → in_progress → terminal` state machine, `voice_call` message bubbles linked to each call, conversation `call_status` tracking, and account-wide realtime call events over ActionCable.
- Enable voice on the existing Twilio and WhatsApp channels (`voice_enabled` flags, TwiML app credentials, Meta calling status) instead of a standalone voice channel type; drop the orphaned `channel_voice` table left over from the fork base.
- Twilio calling: provider webhook endpoints (TwiML, call status, conference events, recording status), named-conference bridging, browser WebRTC token, join/leave conference, outbound dial from a contact or conversation, mute controls, per-inbox inbound-call toggle, per-call recording with background attachment, and a channel health check that compares configured webhooks/account/number capabilities against what the inbox needs.
- WhatsApp Cloud Calling: browser↔Meta WebRTC with SDP offer/answer relay; initiate/accept/reject/terminate API; a throttled call-permission request flow for contacts who have not opted in; support for manually configured (non-embedded signup) WhatsApp Cloud inboxes; browser-captured recording upload.
- Voice notes: record WhatsApp-compatible audio (ogg/opus) from the reply box.
- Calls dashboard: account-scoped call history API with role-based visibility, status/direction/inbox/agent/date filters and pagination, plus a new Calls page with recording playback and transcript display.
- Contact merge: re-point call records to the surviving contact so call history is preserved (call-record side only; the merge flow itself is owned by `companies-management`).
- [EE upstream — clean-room] Per-inbox call recording and transcription toggles, and transcription of completed Twilio call recordings via Pilot speech-to-text.

## Capabilities

### New Capabilities

- `voice-call-core`: The shared call domain — `Call` record, status state machine, voice-call conversation messages, realtime events, display normalization, recording-enablement snapshot, and call-record preservation across contact merges.
- `twilio-voice-channel`: Voice enablement, inbound/outbound calling, conference bridging with agent join, mute and inbound-call controls, recordings, error surfacing, and health monitoring for Twilio channels.
- `whatsapp-cloud-calling`: WhatsApp Cloud Calling over browser↔Meta WebRTC, including the call-permission opt-in flow, non-embedded signup inbox support, browser recording upload, and WhatsApp-compatible voice notes.
- `call-history-dashboard`: The call history API (visibility-scoped, filterable, paginated) and the Calls page in the dashboard.
- `call-recording-transcription`: Per-inbox call recording and transcription settings, and transcription of call recordings through Pilot (clean-room re-expression of the upstream EE feature).

### Modified Capabilities

None. Contact-merge call preservation adds a call-record step to the merge flow owned by `companies-management`; only the call-record side is specced here.

## Impact

- `calls` table (already present from the fork base; new model, scopes, and indexes on `account_id, created_at` may be required).
- `channel_twilio_sms` (new `voice_enabled`, `twiml_app_sid`, `api_key_secret`, `provider_config` columns) and `channel_whatsapp` (provider_config-driven calling flags) — migrations required; `channel_voice` table dropped.
- New core-tree backend: `app/models/call.rb`, `app/services/voice/**`, `app/services/whatsapp/**` call services, Twilio voice webhook controller, account API controllers for calls/conference/WhatsApp calls, background jobs for recording attachment and transcription, routes.
- `Channel::TwilioSms`, `Channel::Whatsapp`, `ContactMergeAction`, conversation/message serializers (embedded call payload on `voice_call` messages).
- Frontend: `components-next/call/*`, `components-next/Calls/*`, `composables/useCallSession.js`, `composables/useWhatsappCallSession.js`, `helper/voice.js`, `stores/calls.js`, new `stores/callHistory.js`, `routes/dashboard/calls/*`, inbox settings pages (voice configuration, WhatsApp calling, call recording), `AudioRecorder` voice-note changes, English i18n (`en/calls.json` and related keys).
- ActionCable event surface: `voice_call.*` account broadcasts consumed by the dashboard.
- Pilot: speech-to-text capability used for call transcription (clean-room).
