## Context

The fork base (v4.13.0) already contains the `calls` table (account/inbox/conversation/contact/message/accepted_by_agent references, `provider_call_id`, `provider` and `direction` enums, `status`, `started_at`, `duration_seconds`, `end_reason`, `meta` jsonb, `transcript`), the `channel_voice` table, and the MIT-licensed first-generation voice frontend. Everything else about calling lived in upstream's `enterprise/` overlay and was deleted with it.

Upstream v4.14.0–v4.18.0 then: kept the unified `Call` model; abandoned the standalone voice channel in favor of `voice_enabled` on `Channel::TwilioSms` (adding `twiml_app_sid` / `api_key_secret`) and a `calling_enabled` flag in `Channel::Whatsapp#provider_config` (whatsapp_cloud provider only); built Twilio calling on named conferences bridged via TwiML webhooks; built WhatsApp Cloud Calling as a browser↔Meta WebRTC session with SDP relayed through the app; added recordings (provider-side for Twilio, browser-captured upload for WhatsApp); added a calls dashboard; and — as EE-tagged features — per-inbox recording/transcription settings and call transcription.

**License axis (mixed).** Per the parity plan, the calling core (everything not EE-tagged in the upstream changelog) is treated as MIT feature work; per-inbox recording/transcription settings and call transcription are EE and specced requirements-level (clean-room). One nuance the implementation must respect: upstream ships the *entire* calling backend under its `enterprise/` directory, which its LICENSE places under the Chatwoot Enterprise License even for features the changelog does not tag as Enterprise. Therefore:

- **Verbatim porting is legal only for files from upstream's MIT tree**: `app/javascript/**` (call UI, composables, stores, routes, i18n, `TwilioHealth.vue`, `CallRecordingSettings.vue`), `db/migrate/**` (voice columns, `channel_voice` drop), `app/services/twilio/health_service.rb`, the `Channel::TwilioSms` / `ContactMergeAction` core diffs.
- **All backend orchestration** (call builders, conference/status managers, webhook controllers, WhatsApp call services, transcription) **must be re-implemented as original code in Konversio's core tree**, guided by the requirements in these specs. Upstream EE files were read for understanding only.
- The EE-tagged features (recording/transcription settings, transcription) are additionally specced in original wording with Pilot naming and no upstream identifiers.

## Goals / Non-Goals

**Goals:**

- One `Call` record per call, shared across Twilio and WhatsApp providers, with a single status state machine and realtime events the dashboard can render uniformly.
- Twilio voice calling end-to-end: inbound webhook → ringing call → browser join → in-progress → terminal, with recordings and a health check.
- WhatsApp Cloud Calling end-to-end, including the permission opt-in flow and manual (non-embedded) signup inboxes.
- A calls dashboard with role-appropriate visibility.
- Call records that survive contact merges.
- Clean-room per-inbox recording/transcription settings and Pilot-based transcription.

**Non-Goals:**

- Video calling (Dyte → Cloudflare RealtimeKit) — owned by `realtimekit-video-calls`.
- WhatsApp platform work (BSUID, coexistence, campaigns, health/business profile beyond calling) — owned by `whatsapp-platform`. This change consumes the multi-identity contact resolution it provides but does not spec it.
- The contact-merge flow itself — owned by `companies-management`; only the call-record reassignment step is specced here.
- Call analytics, outcome metrics, or reporting beyond the list/dashboard surface.
- A standalone `Channel::Voice` channel type (upstream created and then dropped it; see Decisions).

## Decisions

### Voice is a capability flag on existing channels, not a channel type

Upstream first shipped a `Channel::Voice` model backed by a `channel_voice` table (present in our fork base), then migrated to `voice_enabled` + `twiml_app_sid` + `api_key_secret` columns on `channel_twilio_sms` and dropped `channel_voice` (migrations `20260326120000` / `20260326120001`, MIT). Konversio should skip the intermediate state: add the Twilio columns, drive WhatsApp calling from `Channel::Whatsapp#provider_config`, and drop the never-used `channel_voice` table.

Alternatives considered:
- Keep `channel_voice` and build a standalone voice inbox type. Rejected: it forks the data model away from upstream's final shape, duplicates phone-number ownership across channel types, and leaves a dead table to maintain.
- Leave `channel_voice` in place unused. Rejected: dead schema with a unique phone-number index that can collide with real channels.

Rationale: aligning on upstream's final schema keeps future parity work (and the MIT migrations) directly applicable.

### All backend code lands in the core tree as an original implementation

Konversio has no `enterprise/` directory and no `prepend_mod_with` dance. Everything — call model, `Voice::` services, webhook controllers, finders, jobs — lands in `app/`, `lib/`, `db/` under the existing `Voice::` / `Whatsapp::` namespaces (these namespaces are architectural, not copied expression; the class-level logic is re-implemented from the requirements). Upstream's `enterprise/app/services/voice/**`, `enterprise/app/controllers/**`, and `enterprise/app/services/whatsapp/call_*` files serve as behavioral reference only.

Alternatives considered:
- Verbatim-port the enterprise backend since the changelog does not tag those items "[Enterprise]". Rejected: upstream's LICENSE puts the whole `enterprise/` directory under the Enterprise License regardless of changelog tagging; the parity axis classifies the *features* as MIT-tier, not the files.
- Re-create an `enterprise/` overlay for calling. Rejected: Konversio is 100% MIT with no OSS/EE split; an overlay adds indirection with no benefit.

### Twilio bridging via named conferences with first-join-wins claim

Each Twilio call is bridged through a named conference derived from the account and call id. Agents join from the browser using a provider access token; the first agent to join claims the call (`accepted_by_agent`), the claim auto-assigns the underlying conversation if unassigned, and a single exactly-once "accepted" broadcast fires when the provider confirms the agent leg actually joined — not when the join API returns. Later joins by other agents are refused with a conflict. Conference lifecycle events drive status transitions, and terminal statuses are immutable so late provider events cannot reopen or re-label a finished call.

Alternatives considered:
- Accept-on-API-click (mark accepted when the join endpoint returns). Rejected: the browser leg can still fail after the API returns, leaving a call claimed by an agent who never connected.
- Let any number of agents join and track them all. Rejected for v1: multi-party calling is out of scope; a single owner keeps assignment, duration, and UI semantics unambiguous.

### WhatsApp calling as browser↔Meta WebRTC with SDP relay

For WhatsApp, Meta terminates the media; the dashboard browser holds a WebRTC session with Meta directly, and the Rails app relays the SDP offer/answer between the two. Initiate requires an SDP offer; accept requires an SDP answer; reject and terminate are signaling-only. All agent actions serialize on the call row so a webhook racing an agent action cannot overwrite a freshly finalized status, and provider API failures abort the local transition instead of marking a still-live call ended. Inbound calls arrive as webhook call events; a terminate that arrives before its paired connect is tombstoned briefly rather than creating a phantom call.

Alternatives considered:
- Bridging WhatsApp calls through the same conference infrastructure as Twilio. Rejected: Meta's Cloud Calling API is WebRTC-to-Meta, not SIP/conference; there is nothing to bridge into.
- Server-side media relay. Rejected: adds a media server for no product benefit; the browser↔Meta path is what the provider supports.

### Call-permission flow for WhatsApp outbound calls

Meta requires the contact to have granted call permission; dialing without it fails with a distinct provider error. Rather than surfacing a raw failure, the app sends the contact a permission-request message, throttled so repeated dial attempts cannot spam the contact, with an optional per-inbox custom request body and an activity note in the conversation. The contact's affirmative reply is matched back to the request and subsequent dials proceed.

### Conversation continuity rules for calls

Inbound calls resolve contact/conversation through the same multi-identity resolution as inbound messages (phone plus aliases), reuse the latest non-resolved conversation on the resolved contact-inbox (or the single locked conversation on locked inboxes), and otherwise open a new open conversation. Outbound calls reuse the open conversation the agent is looking at only when it belongs to the same inbox and contact and is open; resolved/snoozed threads are never reused because an outgoing call bubble cannot reopen them. Conversation assignment is never stomped: pickup claims the conversation only if it is unassigned.

### Recording semantics: per-call snapshot, provider-specific capture

Whether a call is recorded is snapshotted from the inbox's recording setting at call creation, so every leg agrees and a mid-call settings toggle cannot retroactively change a live call; calls that predate the setting default to recorded. Twilio recordings are captured provider-side (record-from-start on the conference) and delivered via recording-status callback to a background job that downloads and attaches the audio idempotently. WhatsApp recordings are captured in the browser and uploaded after the call; the server independently re-checks the recording setting at upload time because a stale tab may hold an outdated toggle.

### Transcription and per-inbox settings are clean-room (EE upstream)

The per-inbox recording/transcription toggles and the transcription pipeline are specced requirements-level only: original wording, Pilot naming (`Pilot::` speech-to-text capability; any new persistence uses `pilot_`-prefixed tables, though none is expected — the `transcript` column already exists on `calls`), no upstream class names, copy, or constants. Upstream's implementation was read for understanding only. needs investigation: Konversio's Pilot layer currently has no speech-to-text service (`lib/llm` covers chat models only) — the transcription provider configuration, model routing, and any usage accounting must be designed against Pilot's existing config rather than upstream's Captain credentials.

### Calls dashboard visibility mirrors conversation permissions

The call history API is account-scoped: administrators and users with report-manage permission see all calls; everyone else sees only calls they personally accepted within conversations they can access. Filters (status, direction, inbox, agent, date range) accept both stored and display forms. Pagination is fixed at 25 per page, newest first.

### Display normalization is a model concern

Calls store `incoming`/`outgoing` directions and `in_progress`-style statuses, but render `inbound`/`outbound` and hyphenated statuses. The model owns both mappings so API clients and the dashboard can query and display with either form, and the frontend derives row "kinds" (ongoing, incoming, outgoing, missed, no-reply, failed) from status+direction pairs.

## Risks / Trade-offs

- **Re-implementation drift from upstream behavior** -> The specs capture the externally observable contract (state machine, webhooks, API shapes, broadcasts); unit specs should pin transitions and payloads rather than internal structure.
- **Webhook idempotency** -> Provider retries are normal; all webhook handlers must be safe to invoke repeatedly (find-or-create by provider call id, unique index on `(provider, provider_call_id)`, exactly-once broadcast gates).
- **Frontend/backend lockstep** -> The MIT frontend expects specific API shapes (conference token/join/leave, WhatsApp initiate/accept/reject/terminate, calls index); port the frontend and implement the backend to its contract, not the other way around.
- **Recording storage cost** -> Recordings attach via ActiveStorage like other media; no new infrastructure, but retention policy is out of scope here.
- **`channel_voice` table drop** -> The table exists in fork-base schema but was never backed by code in Konversio; confirm emptiness in the migration before dropping.

## Migration Plan

1. Additive migrations first: voice columns on `channel_twilio_sms`, any missing indexes on `calls`. Drop `channel_voice` in the same release after confirming it is empty.
2. Ship backend (model, webhooks, services, jobs, API) and frontend (ported MIT UI) together behind the existing `channel_voice` account feature flag where upstream gates on it.
3. Enable per inbox (Twilio voice toggle / WhatsApp calling toggle); health check verifies webhook configuration before announcing support.
4. Rollback: disable the per-inbox toggles and the feature flag; call records and schema remain harmless.

## Open Questions

- needs investigation: the exact entry point in Konversio's WhatsApp webhook pipeline where call events/statuses should be dispatched to the incoming-call handler (upstream wires this in its EE webhook layer).
- needs investigation: Pilot speech-to-text — provider, model routing, and usage accounting for call transcription (see Decisions).
- Should the Calls page be gated behind the same `channel_voice` feature flag, or always visible once any voice inbox exists? Current assumption: follow upstream's installation/permission gating and show it to all conversation users.
