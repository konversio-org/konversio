## Why

Pilot AI assistants (e.g. Mira) handle real customer conversations, but Konversio records nothing about how those conversations end. Operators cannot answer basic questions — did the AI resolve it alone, was it handed off to a human and why, did the customer come back after an "AI resolution", what was the CSAT — without reading transcripts by hand. The existing AI Agents observability view (see `add-ai-agent-conversation-observability`) derives participation live from message authorship and explicitly defers outcome metrics.

Upstream Chatwoot shipped episode-based Captain outcome tracking as an Enterprise feature in v4.17.0 ("Control Captain audiences, schedules, inactivity handling, outcomes, and knowledge usage"). Konversio needs the equivalent capability as a clean-room, MIT-licensed feature in the core tree.

## What Changes

- Add a `pilot_conversation_outcomes` table storing one row per **outcome episode**: a half-open time window `[started_at, ended_at)` of AI involvement on a conversation, with at most one open episode per conversation at any time.
- Record episode facts: start/end timestamps, first and last AI reply timestamps, AI public reply count, first human reply timestamp, handoff timestamp with a categorized reason, resolution timestamp, and CSAT rating with received timestamp.
- Open the first ("initial") episode when Pilot first becomes eligible to respond on a conversation; open a follow-up episode each time a resolved conversation reopens after a tracked episode existed, closing the predecessor.
- Emit Pilot conversation lifecycle events (handed off with source and categorized reason; resolved) on the internal event bus, and consume them — plus core message/conversation/CSAT events — in a dedicated listener that drives episode recording.
- Categorize every handoff with a governed reason taxonomy; the taxonomy MUST include a category denoting transfers caused by exhaustion of AI usage quota.
- Ensure outcome recording is failure-isolated: a tracking error MUST never alter the customer-facing Pilot flow.

## Capabilities

### New Capabilities
- `pilot-conversation-outcomes`: Episode-grained recording of AI involvement per conversation — lifecycle timestamps, reply facts, categorized handoffs, resolutions, reopen episodes, and CSAT — stored in `pilot_conversation_outcomes`.
- `pilot-conversation-lifecycle-events`: Domain events on the internal event bus describing Pilot conversation state transitions (handed off with source and reason category, resolved), consumable by outcome tracking and future reporting.

### Modified Capabilities
None.

## Impact

- New table `pilot_conversation_outcomes` (migration, `pilot_` prefix per Konversio convention) with reporting and uniqueness indexes.
- New model `Pilot::ConversationOutcome` in the core tree (`app/models/pilot/`).
- New recording service and event listener (`app/services/pilot/`, `app/listeners/`), registered on the dispatcher.
- New event constants in `lib/events/types.rb`; emission points in the Pilot handoff/resolution paths (`Conversation#bot_handoff!` callers, autopilot inference, quota-exhaustion handling).
- CSAT listener wiring (`CsatSurveyResponse`) so survey ratings land on the covering episode.
- No user-facing UI in this change; analytics/reporting surfaces that consume the data are a separate change.
- License: clean-room requirements-level specification of an upstream Enterprise feature — no upstream code, copy, or naming is ported.
