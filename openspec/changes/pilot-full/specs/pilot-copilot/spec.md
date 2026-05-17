## ADDED Requirements

### Requirement: Copilot thread lifecycle

An agent SHALL be able to start, view, and continue Copilot conversation threads scoped to themselves and an account. A thread MUST belong to one user/agent, one account, and one assistant. Conversation context MAY be supplied when creating the first message or subsequent messages; Pilot need not persist `conversation_id` on `copilot_threads` unless a dedicated column is added.

#### Scenario: Agent starts a new thread
- **WHEN** an agent POSTs to `/api/v2/accounts/:account_id/pilot/copilot_threads` with `{"message": "Refund policy question", "assistant_id": 7}`
- **THEN** the response status is `201`
- **AND** a thread is created with `title` derived from the first message
- **AND** the first user message is persisted on the thread

#### Scenario: Thread bound to a customer conversation
- **WHEN** an agent POSTs `{"message": "Drafting reply", "assistant_id": 7, "conversation_id": 42}`
- **THEN** the response-generation job receives `conversation_id = 42` for context

#### Scenario: Agent lists their own threads
- **WHEN** an agent GETs `/api/v2/accounts/:account_id/pilot/copilot_threads`
- **THEN** the response includes only threads where `agent_id` equals the requesting agent

#### Scenario: Cross-agent thread access forbidden
- **WHEN** agent A GETs a thread owned by agent B
- **THEN** the response status is `404` (intentionally not 403 — do not leak existence)

### Requirement: Copilot messages stored and ordered

Each Copilot thread SHALL persist its messages with `message_type` (integer enum: `user=0`, `assistant=1`, `assistant_thinking=2`), JSON `message` payload containing `content`, and `created_at`. Messages MUST be returned in chronological order on message fetch.

#### Scenario: Agent posts a message
- **WHEN** an agent POSTs `{"message": "What's our refund window?", "conversation_id": 42}` to `/api/v2/accounts/:account_id/pilot/copilot_threads/:id/copilot_messages`
- **THEN** a message with `message_type = 0` (user) is persisted
- **AND** a response-generation job is enqueued with the supplied conversation context
- **AND** the response status is `201`

#### Scenario: Assistant reply persisted
- **WHEN** the LLM completes a reply
- **THEN** a message with `message_type = 1` (assistant) and the reply content is persisted in the same thread

#### Scenario: Assistant thinking message persisted
- **WHEN** the underlying agent framework emits intermediate reasoning tokens for an agentic step
- **THEN** a message with `message_type = 2` (assistant_thinking) is persisted in the same thread
- **AND** the UI MAY render thinking messages differently (collapsed by default)

#### Scenario: Messages returned in order
- **WHEN** an agent GETs `/api/v2/accounts/:account_id/pilot/copilot_threads/:id/copilot_messages`
- **THEN** the `messages` array is sorted ascending by `created_at`

### Requirement: Real-time message broadcast on create

When a Copilot message is created (user or assistant), the system SHALL dispatch a `COPILOT_MESSAGE_CREATED` event via the Rails event dispatcher so subscribed clients can render the new message live without polling.

#### Scenario: User message dispatches event
- **WHEN** an agent POSTs a user message and it is persisted
- **THEN** a `COPILOT_MESSAGE_CREATED` event is dispatched with the message payload

#### Scenario: Assistant message dispatches event
- **WHEN** the response job persists the assistant message
- **THEN** a `COPILOT_MESSAGE_CREATED` event is dispatched with the new message payload
- **AND** subscribed dashboard clients receive the message via ActionCable

### Requirement: Assistant responses generated asynchronously

Assistant message generation SHALL run asynchronously rather than blocking the HTTP request. The POST that creates a user message MUST return immediately (HTTP 201) and the resulting assistant message MUST be persisted when the job completes. Live token streaming is optional and MAY be layered on later.

#### Scenario: POST returns before LLM completes
- **WHEN** an agent POSTs a user message
- **THEN** the response is `201` within 1 second
- **AND** the response body contains the persisted user message id but no assistant content yet

#### Scenario: Assistant reply persisted after job completes
- **WHEN** the queued response job completes
- **THEN** an assistant message is persisted in the same thread with the generated content

#### Scenario: Thread refresh shows completed reply
- **WHEN** the client refreshes or reconnects after the job completes
- **THEN** the client GETs the thread messages and finds the completed assistant message

### Requirement: Copilot drawer UI

A drawer-style sidebar SHALL be available in the dashboard for any agent in an account with `pilot_copilot_enabled = true`. The drawer MUST display the active thread's messages, accept input for new user messages, show a pending state while the response job runs, and offer a "new thread" action.

#### Scenario: Drawer accessible from sidebar
- **WHEN** the agent is in an account with `pilot_copilot_enabled = true`
- **THEN** a Copilot icon is rendered in the dashboard sidebar
- **AND** clicking it opens the drawer

#### Scenario: Drawer hidden when disabled
- **WHEN** `pilot_copilot_enabled = false`
- **THEN** no Copilot icon appears in the sidebar

#### Scenario: Pending reply rendering
- **WHEN** the agent sends a message AND the response job is still running
- **THEN** the drawer shows a pending assistant response state until the persisted reply is available

#### Scenario: Bound-conversation context
- **WHEN** the agent opens Copilot from inside a customer conversation view
- **THEN** the new thread/message creation includes that conversation id in the response-generation job
- **AND** the LLM prompt includes the customer conversation transcript as context
