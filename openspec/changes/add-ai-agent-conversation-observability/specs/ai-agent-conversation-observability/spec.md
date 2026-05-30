## ADDED Requirements

### Requirement: AI Agents sidebar group
The system SHALL display an **AI Agents** group in the Conversations sidebar when the account has one or more customer-facing Pilot assistants connected to inboxes.

#### Scenario: Account has connected AI agents
- **WHEN** a conversation user opens the Conversations sidebar for an account with a `Pilot::Assistant` connected through `pilot_inboxes`
- **THEN** the sidebar displays an **AI Agents** group containing that assistant by name

#### Scenario: Account has no connected AI agents
- **WHEN** a conversation user opens the Conversations sidebar for an account without any `Pilot::Assistant` connected through `pilot_inboxes`
- **THEN** the sidebar does not show AI-agent entries

### Requirement: AI Agent channel coverage
The system SHALL show each visible AI agent with its connected inbox/channel coverage and SHALL allow users to drill into a specific connected inbox/channel.

#### Scenario: AI agent has multiple connected inboxes
- **WHEN** an AI agent is connected to more than one inbox
- **THEN** the sidebar shows the AI agent with child entries for each connected inbox/channel

#### Scenario: User selects AI agent channel child
- **WHEN** a user selects an AI agent's connected inbox/channel child entry
- **THEN** the conversation list is filtered to conversations from that inbox where the selected AI agent participated

### Requirement: AI Agent participation filter
The system SHALL filter conversations by AI-agent participation using existing message authorship data.

#### Scenario: User selects an AI agent
- **WHEN** a user selects an AI agent from the **AI Agents** sidebar group
- **THEN** the conversation list includes conversations containing at least one message with `sender_type = 'Pilot::Assistant'` and `sender_id` equal to the selected AI agent id

#### Scenario: Conversation has no selected AI agent message
- **WHEN** a conversation has no message authored by the selected AI agent
- **THEN** the conversation does not appear in that AI agent's filtered list

#### Scenario: Existing conversation permissions apply
- **WHEN** a user selects an AI agent filter
- **THEN** the conversation list only includes conversations the user is already permitted to access

### Requirement: AI Agent card chip
The system SHALL show a compact AI-agent chip on conversation cards when a visible AI agent participated in that conversation.

#### Scenario: Conversation has AI agent participation
- **WHEN** a conversation card represents a conversation with at least one message authored by a visible AI agent
- **THEN** the card displays a compact chip with that AI agent's name

#### Scenario: Conversation has no AI agent participation
- **WHEN** a conversation card represents a conversation without visible AI-agent participation
- **THEN** the card does not display an AI-agent chip

### Requirement: No business labels for AI Agents
The system SHALL NOT create, update, or require conversation labels to represent AI-agent participation.

#### Scenario: AI agent participates in conversation
- **WHEN** an AI agent sends a message in a conversation
- **THEN** the system can surface AI-agent participation without applying a conversation label named after the AI agent

### Requirement: Product naming
The system SHALL use **AI Agents** for the user-facing Conversations sidebar feature while preserving existing internal `Pilot::Assistant` persistence and API naming for this change.

#### Scenario: User views the sidebar group
- **WHEN** the AI-agent observability group is rendered in the Conversations sidebar
- **THEN** its user-facing label is **AI Agents**

#### Scenario: System queries Pilot records
- **WHEN** the system loads AI-agent sidebar data or filters AI-agent conversations
- **THEN** it uses existing `Pilot::Assistant` records as the backing data source

### Requirement: AI Agent lifecycle tabs
The system SHALL replace the human-centric conversation tabs (Mine, Unassigned, All) with AI-agent lifecycle-based tabs when viewing conversations filtered by an AI Agent.

#### Scenario: User views AI Agent conversation list
- **WHEN** an AI Agent view is active
- **THEN** the conversation tabs shown at the top are:
  - **Active (Autopilot)**: Displays open, unassigned conversations containing the AI agent's messages.
  - **Handed Off**: Displays open, assigned conversations containing the AI agent's messages.
  - **Resolved (Contained)**: Displays resolved, unassigned conversations containing the AI agent's messages.
