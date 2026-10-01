## Context

Pilot assistants participate in customer conversations through the core message pipeline: AI replies are ordinary outgoing messages whose sender is the `Pilot::Assistant`, handoffs run through `Conversation#bot_handoff!` (which also stamps `additional_attributes['pilot_handoff']` metadata), and resolutions go through the core `conversation_resolved` event. None of this leaves a durable, queryable record of *how the AI's involvement went* — only the raw transcript.

Upstream Chatwoot v4.17.0/v4.18.0 implements this as an Enterprise feature: an episode-grained outcomes table, a recording service, lifecycle domain events, and an event listener, all under `enterprise/`. That implementation is **EE-licensed reference material only**. This change specifies the equivalent capability for Konversio at the requirements level: behavior, state machine, data shape, and event contracts are described in original wording, targeted at Konversio's `Pilot::` namespace in the core tree. No upstream file names, class names, category-string taxonomies, prompt text, or code are carried over.

## Goals / Non-Goals

**Goals:**

- Persist one outcome episode row per continuous window of potential AI involvement on a conversation, in `pilot_conversation_outcomes`.
- Capture per-episode facts: window boundaries, AI reply count and first/last AI reply times, first human reply time, handoff time with categorized reason, resolution time, CSAT rating and receipt time.
- Reopen handling: resolving then reopening a conversation closes the open episode and starts a new one, attributed to the assistant currently attached to the inbox when one exists.
- Categorized handoff reasons from every handoff path (AI-initiated, inference-driven, inactivity-driven, quota-driven).
- Lifecycle domain events on the internal event bus for handoff and resolution, decoupled from the flows that trigger them.
- Failure isolation: tracking and event dispatch failures are logged and reported to the exception tracker but never change customer-facing behavior.

**Non-Goals:**

- Analytics UI, overview/drill-down dashboards, resolution-trend or funnel charts, and AI-generated outcome summaries (separate change; this one only records data).
- Classification/reporting semantics built on episodes (containment, durability windows, saved-time estimates) — the data model must *permit* them, but they are not specced here.
- Backfilling episodes from historical conversations or from `additional_attributes['pilot_handoff']` metadata.
- Any user-facing surface; this change is backend-only.
- Upstream naming compatibility (`conversation_outcomes`, `Captain::*`, `captain.*` event names). Konversio uses its own names throughout.

## Decisions

### Clean-room boundary

The upstream Enterprise implementation (`enterprise/` tree at v4.18.0) was read to understand the *behavioral contract* — which events exist, what an episode is, which facts are snapshotted, which messages count as human replies. Everything below is expressed as original requirements against Konversio's architecture. Alternatives considered:

- Port the upstream files mechanically and rename Captain → Pilot. Rejected: the `enterprise/` tree is EE-licensed; verbatim or lightly-reworded porting is not permitted in this MIT-only fork, per the standing audit guidance.
- Design from scratch without reading upstream. Rejected: the parity goal is behavioral equivalence for reporting; ignoring the reference risks missing load-bearing semantics (e.g. automation/campaign messages not counting as human replies, usage-limit handoffs being distinguishable from genuine escalations).

Rationale: requirements-level re-expression gives behavioral parity without copying expression.

### Episode grain instead of one row per conversation

Each conversation has an ordered stream of episodes: a half-open window `[started_at, ended_at)` with at most one open (`ended_at IS NULL`) episode at a time. Upstream itself migrated from a one-row-per-conversation design to episode grain before release, because reopen-after-resolution otherwise overwrites or confuses outcome facts. Alternatives considered:

- One row per conversation with reopen counters. Simpler schema, but attributes reopen activity to the wrong window and loses per-episode handoff/resolution facts — this is the design upstream abandoned.
- Full event log with derived episodes. More flexible, but pushes reconstruction cost onto every report query.

Rationale: episode grain keeps each row a complete, terminal snapshot of one involvement window, which is what reporting needs.

### Integrity enforced by partial unique indexes

At most one open episode per (account, conversation), at most one initial episode per (account, conversation), and uniqueness of (account, conversation, started_at) are enforced with partial unique indexes in Postgres, not application-level checks. Rationale: recording happens on background/event paths where races are realistic; the database is the only reliable arbiter.

### Recording service + dedicated listener, event-driven handoffs

A single recording service in the `Pilot::` namespace owns all writes to the table. A dedicated listener (separate from `PilotResolveListener`, which owns resolve-time mining) subscribes to: core `message_created` (first-human-reply detection), core `conversation_resolved` (resolution), conversation status changes away from `resolved` (reopen), CSAT survey responses (rating capture), and the new Pilot lifecycle events (handoff). Handoff facts travel as **domain events with a timestamp, source, and reason category payload** rather than direct service calls from the inference/handoff code. Alternatives considered:

- Record handoffs inline where `bot_handoff!` is invoked. Rejected: couples tracking correctness to every call site and makes a tracking failure able to break a customer-facing escalation.
- Fold outcome recording into `PilotResolveListener`. Rejected: that listener is resolve-scoped; outcome recording needs message, reopen, CSAT, and handoff signals too.

### Reply facts are snapshotted at terminal moments

AI reply count and first/last AI reply timestamps are recomputed from messages inside the episode window when a handoff or resolution is recorded, not incremented per message. Rationale: the episode row is a terminal snapshot; maintaining live counters per message adds write load and drift risk for no consumer, since reporting reads completed snapshots. A side effect: episodes that never terminate have zero/NULL reply facts until their first terminal event — acceptable for v1 since reporting targets completed windows. needs investigation: whether near-real-time dashboards (a later change) require per-message counter maintenance.

### What counts as a human reply

A message counts as the episode's first human reply only if it is a public, outgoing, non-private message authored by a human agent — including human replies echoed back from external channels — and excluding messages generated by automation rules and campaign outreach. Rationale: without these exclusions, bulk campaigns and rule-based auto-replies would falsify "human took over" signals, corrupting containment measurement.

### Usage-limit handoffs are a first-class category

The handoff reason taxonomy MUST distinguish transfers caused by AI usage-quota exhaustion from genuine escalations, because a quota block that occurs *before the AI ever replied* represents blocked demand rather than a failed conversation, and downstream classification treats it differently from a mid-conversation transfer. The full taxonomy is owned by the model and MUST be extensible; the AI's handoff tool and every system-driven handoff path MUST supply a category from it. needs investigation: the final category set for Konversio (upstream's exact strings are EE expression and deliberately not adopted; Konversio should define its own minimal taxonomy covering at least customer-initiated escalation, knowledge/capability gap, policy or scope refusal, system/tool failure, and quota exhaustion).

### Tracking-start watermark

The system exposes the timestamp at which outcome recording began (creation time of the earliest episode), cached, so future reporting can mark earlier periods as untracked rather than as zero. Rationale: without a watermark, pre-feature history is indistinguishable from "the AI did nothing".

### Episode trigger labels

Each episode records what opened it (first eligibility vs. reopen). Upstream's enum also reserves an assignment-driven trigger with no producer in v4.18.0. needs investigation: whether a conversation reassigned between inboxes/assistants mid-stream should open a distinct episode or continue the open one; v1 specs only initial and reopen triggers.

## Risks / Trade-offs

- **Dual-write drift with `pilot_handoff` metadata** -> `additional_attributes['pilot_handoff']` remains the operational handoff state; episodes are the reporting record. Listeners must tolerate either being absent; do not try to keep them transactionally consistent.
- **Event ordering races** (resolution event processed before the episode-opening path) -> recordings are idempotent and nil-safe; a terminal event with no covering episode is a no-op, not an error.
- **Episode window attribution for CSAT** -> the rating lands on the episode whose window covers the survey-response message's creation time; responses arriving after all episodes closed attribute to the last closed episode covering that time, and to nothing if none covers it.
- **Query growth on messages** -> reply snapshots scan messages by `conversation_id` + `created_at` range; existing message indexes are expected to suffice (needs verification under production plans before adding indexes).

## Migration Plan

1. Add table, model, events, listener, and recording service with recording gated on the existing `pilot` account feature flag.
2. Wire emission of lifecycle events into the Pilot handoff/resolution paths.
3. Rollback: remove listener registration and emission points, drop the table. Conversations, messages, and `pilot_handoff` metadata are untouched; no data migration is involved.

## Open Questions

- Should episode opening be gated only on an attached `Pilot::Inbox`, or also on the assistant's autopilot/enabled state? v1 assumes attached-and-active at message time, matching the eligibility hook point.
- Which exact hook opens the initial episode in Konversio's flow (autopilot inference job entry vs. message-template hook path)? needs investigation at implementation time; the spec fixes the *semantics* (first moment Pilot is eligible to respond), not the call site.
