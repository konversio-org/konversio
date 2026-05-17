## ADDED Requirements

### Requirement: Assistant lifecycle

An admin SHALL be able to create, configure, list, edit, and delete Autopilot assistants scoped to an account. An assistant MUST have a `name`, `description`, JSON `config`, optional `response_guidelines`, optional `guardrails`, inbox associations through `captain_inboxes`, and an enabled/disabled state derived from account/inbox attachment. The config MUST support Captain-compatible keys including `product_name`, `feature_faq`, `feature_memory`, `feature_contact_attributes`, `feature_citation`, `welcome_message`, `handoff_message`, `resolution_message`, `instructions`, and `temperature`.

#### Scenario: Admin creates an assistant
- **WHEN** an admin POSTs `{"name": "Support Bot", "description": "Answers support questions", "config": {"product_name": "Konversio"}}` to `/api/v2/accounts/:account_id/pilot/assistants`
- **THEN** the response status is `201`
- **AND** a `Captain::Assistant` row is persisted with `account_id`, `name`, `description`, and `config`

#### Scenario: Admin attaches assistant to inbox
- **WHEN** an admin PATCHes an assistant with `{"inbox_ids": [7]}`
- **THEN** a `captain_inboxes` row is created linking the assistant to inbox 7

#### Scenario: Disabled assistant skips inference
- **WHEN** a customer message arrives at an inbox whose assistant has `enabled = false`
- **THEN** no LLM call is made AND the conversation is not auto-replied to

### Requirement: Document ingestion with embeddings

Each assistant SHALL accept knowledge-source documents as `Captain::Document` rows with `external_link`, optional PDF attachment, `content`, `metadata` (JSONB), `status`, and `sync_status`. A document is a source record; searchable knowledge is stored as generated `Captain::AssistantResponse` rows associated polymorphically to the document, each with an embedding in `captain_assistant_responses.embedding`.

The document MUST track two independent state fields:
- `status` (document availability lifecycle): `in_progress` → `available`
- `sync_status` (async fetch operation result): `syncing` → `synced` (success) | `failed`

`external_link` MUST be unique per assistant. Documents with no externally-supplied link (PDF uploads) MUST receive an auto-generated link of the form `PDF: <filename>_<ISO8601_timestamp>` to satisfy that constraint.

#### Scenario: Admin uploads a document
- **WHEN** an admin POSTs `{"name": "Refund Policy", "external_link": "https://example.com/help/refunds"}` to `/api/v2/accounts/:account_id/pilot/assistants/:id/documents`
- **THEN** a `Captain::Document` row is persisted with `status = "in_progress"` and `sync_status = "syncing"`
- **AND** `Captain::Documents::CrawlJob` is enqueued unconditionally for the new document

#### Scenario: Crawl success transitions both status fields
- **WHEN** the crawl job successfully fetches content for a document
- **THEN** the document's `content` is populated
- **AND** `status` becomes `"available"`
- **AND** `sync_status` becomes `"synced"`
- **AND** `Pilot::Documents::ResponseBuilderJob` is enqueued for that document

#### Scenario: Crawl failure leaves status unchanged
- **WHEN** the crawl job fails (HTTP error, timeout, parse error)
- **THEN** `sync_status` becomes `"failed"`
- **AND** `status` remains `"in_progress"`
- **AND** `metadata` records the failure cause (HTTP status, error message)
- **AND** no `ResponseBuilderJob` is enqueued

#### Scenario: ResponseBuilderJob generates assistant responses
- **WHEN** `Pilot::Documents::ResponseBuilderJob` runs for an available document
- **THEN** the LLM generates question/answer pairs from the document content
- **AND** each pair is persisted as a `Captain::AssistantResponse` linked polymorphically to the document
- **AND** each response is embedded into `captain_assistant_responses.embedding` (1536-dim)
- **AND** each response's `status` is `"pending"` until an admin approves it

#### Scenario: Document deleted cascades to derived responses
- **WHEN** an admin DELETEs a document
- **THEN** the document row is destroyed
- **AND** all `Captain::AssistantResponse` rows derived polymorphically from it are removed

#### Scenario: URL ingestion via Firecrawl
- **WHEN** `PILOT_FIRECRAWL_API_KEY` is configured AND the crawl job runs for a web document
- **THEN** Firecrawl is invoked to fetch and clean the page
- **AND** the cleaned content is stored as the document body

#### Scenario: URL ingestion fallback to simple page crawl
- **WHEN** `PILOT_FIRECRAWL_API_KEY` is NOT configured AND the crawl job runs for a web document
- **THEN** an in-process HTTP fetch with HTML stripping is performed
- **AND** the resulting content is stored as the document body

#### Scenario: PDF ingestion
- **WHEN** an admin uploads a PDF file
- **THEN** the file MUST be a PDF and no larger than 10 MB
- **AND** the document receives an auto-generated `external_link` of the form `PDF: <filename>_<ISO8601_timestamp>`

#### Scenario: Duplicate external_link rejected per assistant
- **WHEN** an admin POSTs a second document with an `external_link` that already exists for the same assistant
- **THEN** the response status is `422`

### Requirement: Assistant responses form the searchable knowledge base

Pilot SHALL expose CRUD and filtering for `Captain::AssistantResponse` rows. Responses MUST belong to an assistant and account, MAY reference a document/user/conversation through the existing polymorphic `documentable`, MUST have `question`, `answer`, `status` (`pending` or `approved`), optional `edited`, and a 1536-dimension embedding.

#### Scenario: Admin creates a manual response
- **WHEN** an admin POSTs `{"question": "What is the refund window?", "answer": "30 days", "assistant_id": 7, "status": "approved"}` to `/api/v2/accounts/:account_id/pilot/assistant_responses`
- **THEN** a `Captain::AssistantResponse` row is created for the account
- **AND** embedding refresh is enqueued

#### Scenario: Responses can be filtered
- **WHEN** an admin lists responses with `assistant_id`, `document_id`, `status`, or `search`
- **THEN** only matching account-scoped responses are returned

#### Scenario: Bulk response status updates
- **WHEN** an admin submits a bulk action for response ids and `status`
- **THEN** those account-scoped responses are updated together

### Requirement: Assistant inbox attachment endpoints

Pilot SHALL expose endpoints for listing, attaching, and detaching inboxes for an assistant through `captain_inboxes`.

#### Scenario: Admin attaches assistant to inbox
- **WHEN** an admin POSTs `{"inbox_id": 7}` to the assistant inbox endpoint
- **THEN** a `captain_inboxes` row links the assistant to inbox 7

#### Scenario: Admin detaches assistant from inbox
- **WHEN** an admin DELETEs the assistant inbox link for inbox 7
- **THEN** the `captain_inboxes` row is destroyed

### Requirement: Customer-facing chat answers from knowledge base

When a customer sends a message in an inbox attached to an enabled Autopilot assistant, the assistant SHALL build message history from the conversation, offer a built-in documentation-search tool backed by approved `Captain::AssistantResponse` embeddings, generate a reply, and post it as an outgoing message from the assistant.

#### Scenario: Customer message triggers reply
- **WHEN** a customer sends "How long do I have to ask for a refund?" in an inbox with assistant `Support Bot`
- **THEN** a vector search runs against approved `Captain::AssistantResponse` rows for `Support Bot`
- **AND** the most relevant answers are available to the LLM through documentation search
- **AND** a `Message` with `message_type = outgoing` and `sender = Captain::Assistant` is created with the assistant's reply

#### Scenario: No matching documents returns fallback
- **WHEN** the assistant cannot answer from context or tool results
- **THEN** the assistant replies with the configured fallback message
- **OR** the assistant triggers handover (see Handover requirement)

### Requirement: Handover to human agent

An assistant SHALL hand the conversation off to a human agent when the LLM response explicitly requests handover or when a handoff tool/scenario fires. On handover, the assistant MUST stop auto-replying, call the conversation's bot-handoff behavior, and post the configured handoff message or localized default.

#### Scenario: LLM requests handover
- **WHEN** the LLM response is the handover sentinel
- **THEN** the assistant does not post that sentinel as a normal reply
- **AND** the conversation is handed off to a human
- **AND** a customer-facing handoff message is posted

#### Scenario: Customer asks for a human
- **WHEN** the customer message matches phrases like "speak to a human" / "human agent" / "talk to someone"
- **THEN** handover triggers immediately
- **AND** the configured handoff message is posted

#### Scenario: Scenario rule triggers handover
- **WHEN** an enabled scenario or handoff tool matches the customer message
- **THEN** handover triggers
- **AND** the conversation becomes visible to human agents

### Requirement: Scenarios define rule-based behavior

An admin SHALL be able to configure scenarios on an assistant. A scenario MUST have `title`, `description`, `instruction`, `enabled`, and resolved tool references. Scenario instructions MAY reference built-in or custom tools using markdown link syntax `[Label](tool://<tool_id>)`; on save, referenced tool ids MUST be extracted and stored in the scenario's `tools` JSONB field. Invalid tool references MUST make the scenario invalid.

#### Scenario: Tool ID resolved from markdown link
- **WHEN** a scenario instruction contains `[Look up order](tool://lookup_order)`
- **THEN** the tool id `lookup_order` is extracted on save
- **AND** the scenario's `tools` JSONB array includes `lookup_order`

#### Scenario: Invalid tool reference rejected
- **WHEN** a scenario instruction references an unknown tool id (e.g. `[X](tool://does_not_exist)`)
- **THEN** validation fails with an instruction error AND the scenario is not saved

#### Scenario: Enabled scenario registers as handoff trigger
- **WHEN** a scenario has `enabled = true` AND is used by an assistant during inference
- **THEN** the scenario is registered with the agent framework as a callable tool with name `handoff_to_<scenario_key>`
- **AND** the constructed tool name MUST NOT exceed 60 characters (the agent framework's per-tool name limit)
- **AND** scenarios whose constructed name would exceed 60 characters MUST fail validation at save time

### Requirement: Assistant playground

An admin SHALL be able to test an assistant from inside the dashboard without involving a real customer conversation. A `POST /api/v2/accounts/:account_id/pilot/assistants/:id/playground` endpoint MUST accept `message_content` and optional `message_history` entries and return the assistant's reply.

#### Scenario: Playground returns reply
- **WHEN** an admin POSTs `{"assistant": {"message_content": "test", "message_history": [{"role": "user", "content": "hello"}]}}` to the playground endpoint
- **THEN** the response includes the assistant's reply
- **AND** no `Message` or `Conversation` rows are persisted

#### Scenario: Playground supports current-message de-duplication
- **WHEN** the latest history item already matches `message_content`
- **THEN** the playground request does not append a duplicate user message before inference

### Requirement: Autopilot management UI

The dashboard SHALL expose a Pilot → Autopilot section visible when `account.pilot_autopilot_enabled = true`. The section MUST allow admins to manage assistants, their documents, their scenarios, and to run the playground.

#### Scenario: Section visible with flag
- **WHEN** an admin opens an account with `pilot_autopilot_enabled = true`
- **THEN** a "Pilot → Autopilot" link appears in the settings navigation

#### Scenario: Section hidden without flag
- **WHEN** `pilot_autopilot_enabled = false`
- **THEN** the link does not appear AND the route returns `404`
