## Why

Customer-facing Pilot AI agents such as Mira now respond on real support channels, but the Conversations inbox does not expose which conversations they touched. This makes QA, operational review, and future outcome reporting dependent on manual probes, scripts, and transcript inspection.

## What Changes

- Add an **AI Agents** group to the Conversations sidebar, parallel to the existing Channels group.
- List customer-facing Pilot records with connected inboxes as AI agents, while keeping the existing internal `Pilot::Assistant` model/table/API naming for this change.
- Show each AI agent with the channels/inboxes it is active on.
- Allow users to filter the conversation list by AI agent participation.
- Replace the legacy human-centric conversation tabs (Mine, Unassigned, All) with AI-agent lifecycle-based tabs when an AI Agent view is active:
  - **Active (Autopilot)**: Conversations currently being handled by Mira (no human intervention yet; i.e., open and unassigned to any human agent).
  - **Handed Off**: Conversations that Mira was handling, but have since been handed off to a human agent (i.e., open and assigned to a human agent).
  - **Resolved (Contained)**: Conversations that Mira successfully resolved on autopilot without human intervention (i.e., resolved/closed and unassigned to a human agent).
- Allow users to drill into an AI agent by channel/inbox, for example `Mira -> WhatsApp` or `Mira -> Web`.
- Add a compact AI-agent chip to conversation cards when a listed AI agent has participated in the conversation.
- Derive participation from existing message authorship data instead of creating business labels.
- Implement a non-intrusive "spectator mode" when viewing conversations from the AI Agent view: opening a conversation does not clear its unread count or update the operator's last seen timestamp.


## Capabilities

### New Capabilities
- `ai-agent-conversation-observability`: Surfaces customer-facing Pilot AI agent participation in the Conversations sidebar and conversation cards, with filters by AI agent and channel.

### Modified Capabilities

None.

## Impact

- Conversations sidebar navigation and routing/filter state.
- Conversation list query/filter API or existing conversation filter plumbing.
- Conversation card presenter/API payloads needed to render AI-agent participation chips.
- Pilot assistant/inbox associations (`pilot_assistants`, `pilot_inboxes`) used as the source for visible AI agents and channel coverage.
- Message authorship filtering for `sender_type = 'Pilot::Assistant'`.
- English frontend i18n only for new labels and copy.
