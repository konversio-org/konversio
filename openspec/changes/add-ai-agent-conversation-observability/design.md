## Context

Pilot already stores customer-facing AI workers as `Pilot::Assistant` records, connects them to inboxes through `pilot_inboxes`, and writes AI-authored outgoing messages with `sender_type = 'Pilot::Assistant'`. The Conversations sidebar currently exposes conversation entry points such as folders, teams, channels, and labels, but it has no AI-specific surface. As a result, users cannot quickly answer which conversations Mira or a future AI worker participated in.

The product-facing label for this feature is **AI Agents**. The existing internal domain remains **Assistant** for this change to avoid a broad model/table/API rename while shipping the observability surface.

## Goals / Non-Goals

**Goals:**

- Add a Conversations sidebar group named **AI Agents**.
- Show only customer-facing Pilot assistants that are attached to at least one inbox.
- Show each AI agent's attached channel/inbox coverage.
- Filter the conversation list by AI-agent participation, optionally narrowed to an attached inbox/channel.
- Render a compact AI-agent chip on conversation cards when a listed AI agent participated.
- Reuse existing Pilot, message, inbox, route, and conversation-list patterns where possible.

**Non-Goals:**

- Rename `Pilot::Assistant`, `pilot_assistants`, existing API paths, or frontend Pilot store modules.
- Build outcomes reporting, deflection metrics, quality monitoring, or per-reply trace views.
- Add business labels for AI agents.
- List internal assistants that are not connected to customer-facing inboxes.
- Change assignment semantics; AI agents are participants, not human assignees.

## Decisions

### Keep internal Assistant naming in v1

Use **AI Agents** in UI/i18n and docs, but continue to use `Pilot::Assistant` internally.

Alternatives considered:
- Rename the model/table/API now. This would align vocabulary but expands the change into migrations, route/store churn, compatibility concerns, and high regression risk.
- Keep the UI as **Assistants**. This matches code but weakens the desired product language and does not distinguish the new sidebar group from existing Pilot settings copy.

Rationale: the value of v1 is observability in the inbox. Naming cleanup can be handled as a separate domain rename if **AI Agents** becomes the durable product language.

### Derive participation from message authorship

The AI-agent conversation filter should return conversations that have at least one message where `sender_type = 'Pilot::Assistant'` and `sender_id` matches the selected `Pilot::Assistant` id. Channel drill-down adds the selected inbox constraint.

Alternatives considered:
- Auto-apply labels when an AI agent replies. This reuses label filtering and visible chips, but pollutes business labels and can drift on rename/delete.
- Store denormalized conversation participation rows. This may help later analytics, but is not required for the v1 surface.

Rationale: authored messages are already the source of truth and self-maintain as assistants and channels change.

### Add dedicated conversation list parameters

Extend the normal conversation index path with explicit parameters such as `pilot_assistant_id` and optional `inbox_id`, handled in `ConversationFinder` after permission scoping. Add corresponding frontend routes for AI-agent filtered views rather than forcing this through saved custom filters.

Alternatives considered:
- Use the advanced filter endpoint. That is better for user-composed filters but awkward for a first-class sidebar entry and card navigation.
- Encode the filter only in query params on the dashboard route. That avoids routes but makes active sidebar state and conversation detail URLs less consistent with existing Channels/Teams patterns.

Rationale: Channels already have dedicated routes and sidebar active states. AI Agents should follow that pattern for predictable navigation.

### Expose sidebar data from existing Pilot assistant records

Fetch or reuse the Pilot assistants collection and derive visible entries by keeping assistants with attached inboxes. Each child item should represent an attached inbox/channel, using the same channel icon helper/component as Channels where practical.

Alternatives considered:
- Add a bespoke observability navigation endpoint. This may become useful once v2 metrics exist, but v1 can be built from existing assistant and inbox payloads unless the current API payload lacks enough inbox metadata.

Rationale: a self-maintaining list avoids manual configuration and keeps new attached inboxes visible automatically.

### Include card chip metadata in conversation payloads

Conversation list payloads should include a small `pilot_assistants`/`ai_agents` summary for AI agents that participated in each conversation, enough to render chips without loading full messages per card. The chip should use the visible AI agent name and must not be implemented as a label.

Alternatives considered:
- Compute chips purely client-side from messages already loaded. The list view does not always have the full message history, so this would be incomplete.
- Query participation separately per conversation from the card component. This risks N+1 network requests.

Rationale: list payload metadata is the simplest reliable source for a scannable card chip.

### Replace human-centric list tabs with AI-lifecycle tabs

When an AI Agent route is active, replace the legacy "Mine", "Unassigned", and "All" tabs with AI-agent lifecycle-based tabs:
- **Active (Autopilot)**: Conversations currently being handled by the AI (no human intervention yet; i.e., open and unassigned to any human agent).
- **Handed Off**: Conversations that the AI was handling, but have since been handed off to a human agent (i.e., open and assigned to a human agent).
- **Resolved (Contained)**: Conversations that the AI successfully resolved on autopilot without human intervention (i.e., resolved/closed and unassigned to a human agent).

Alternatives considered:
- Keep the legacy tabs and require users to mentally map "Mine" to "conversations assigned to me that the AI touched". This is confusing and exposes outdated human-only assumptions in the AI Agent view.
- Hide the tabs completely and show a flat list. This is simpler to implement but loses the ability to distinguish active AI conversations from those that have been handed off or resolved.

Rationale: AI-lifecycle tabs align the interface with the AI agent's operational workflow, providing clear visibility into active automation versus human handoffs.

### Non-intrusive Spectator Mode for AI Agent Monitoring

When viewing a conversation through the AI Agents view, opening a conversation should be completely non-intrusive (a "spectator mode"). Clicking to view a conversation should not mark it as read or call the `update_last_seen` API. The unread/read state of these conversations must be preserved so that other human support workflows are not disrupted. The conversation will only be marked as read if a human agent takes explicit action, such as assigning it to themselves or sending a reply.

## Risks / Trade-offs

- **Assistant/AI Agent vocabulary split** -> Keep the split explicit in design and code comments where necessary; avoid introducing new internal `ai_agent` persistence names during v1.
- **Conversation list query performance** -> Use joins/subqueries scoped by account, permissions, `sender_type`, and `sender_id`; add indexes only if existing message indexes are insufficient under local/prod query plans.
- **Duplicate rows from message joins** -> Ensure conversation queries use `distinct` or subqueries when joining messages for participation.
- **Sidebar overpopulation** -> Show only assistants with attached inboxes; hide internal assistants such as Kris3000 until they become customer-facing.
- **Ambiguous "handled" language** -> UI and specs should say participated/touched, not resolved/handled, until outcome metrics exist.

## Migration Plan

1. Ship additive API/filter/payload changes without data migrations unless query analysis proves an index is required.
2. Add frontend routes, sidebar entries, and chips behind normal Pilot data availability.
3. Rollback by removing the sidebar group/routes/chips and ignoring the additive filter params; existing conversations and Pilot data remain unchanged.

## Open Questions

- Should "active on a channel" mean attached via `pilot_inboxes` only, or attached plus an enabled autopilot/bot state? V1 should start with attached inboxes unless implementation discovers a reliable enabled flag already used by Pilot.
- Should the sidebar group be visible to all conversation users, or gated to admins/QA roles? The current proposal assumes the same conversation permissions as Channels.
