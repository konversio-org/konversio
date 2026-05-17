## ADDED Requirements

### Requirement: Logbook entry schema

A new `pilot_logbook_entries` table SHALL store per-contact memories. Each entry MUST have `contact_id` (foreign key), `account_id`, `content` (text), `source_message_id` (nullable foreign key to `messages`), `extracted_at` (timestamp), and `created_at`/`updated_at`. The table MUST have an index on `(contact_id, created_at)`.

#### Scenario: Entry references contact
- **WHEN** a Logbook entry is created
- **THEN** the entry's `contact_id` matches an existing `Contact` row
- **AND** the entry's `account_id` equals that contact's account

#### Scenario: Entry survives source message deletion
- **WHEN** the source message is destroyed
- **THEN** the Logbook entry persists with `source_message_id = NULL`

### Requirement: Extraction triggers on conversation resolution

When a `Conversation` transitions to status `resolved` AND `account.pilot_logbook_enabled = true`, a `Pilot::LogbookExtractionJob` SHALL be enqueued for that conversation. Real-time extraction during active conversations is explicitly out of scope.

This behavior is Pilot's adaptation of Captain's resolved-conversation listener: Captain generates contact notes when assistant memory is enabled and generates FAQ responses when assistant FAQ learning is enabled. Pilot stores durable contact memory in `pilot_logbook_entries`, while FAQ/knowledge extraction belongs to Autopilot assistant responses.

#### Scenario: Job enqueued on resolve
- **WHEN** a conversation is updated from `open` to `resolved` AND `pilot_logbook_enabled = true`
- **THEN** `Pilot::LogbookExtractionJob` is enqueued with the conversation id

#### Scenario: FAQ learning remains separate
- **WHEN** a conversation resolves for an assistant with FAQ learning enabled
- **THEN** FAQ-style knowledge extraction creates pending `Captain::AssistantResponse` rows
- **AND** Logbook extraction does not store FAQ entries as contact facts

#### Scenario: No job when feature disabled
- **WHEN** a conversation resolves AND `pilot_logbook_enabled = false`
- **THEN** no extraction job is enqueued

#### Scenario: Re-resolution does not re-extract
- **WHEN** a conversation transitions resolved → reopened → resolved
- **THEN** an extraction job is enqueued only the second time IF new messages arrived in between
- **OTHERWISE** no job is enqueued (idempotency by transcript hash)

### Requirement: LLM-based fact extraction with deduplication

The extraction job SHALL pass the resolved conversation transcript to an LLM that returns a list of durable contact facts. The extraction prompt and parsing behavior MAY follow the pattern Captain uses for `Contact::Note` generation (Captain's `Captain::Llm::ContactNotesService` is the behavioral reference — Pilot does NOT call it directly; Pilot persists into its own `pilot_logbook_entries` table). New entries MUST be deduplicated against the contact's existing Logbook entries via embedding similarity before insertion using cosine similarity with a threshold of `0.92` (configurable via the constant `Pilot::Logbook::DEDUP_SIMILARITY_THRESHOLD`).

#### Scenario: New durable facts inserted
- **WHEN** the LLM returns `["Prefers email over phone", "Has a corporate account"]` for contact 42 with no existing entries
- **THEN** two `pilot_logbook_entries` rows are created with those contents

#### Scenario: Duplicate facts skipped
- **WHEN** the LLM returns `"Prefers email over phone"` AND an existing entry for contact 42 has identical content (or cosine similarity > 0.92)
- **THEN** no new row is inserted

#### Scenario: Soft cap enforced per contact
- **WHEN** a contact has 100 Logbook entries AND extraction would insert a new one
- **THEN** the oldest entry is destroyed first
- **AND** the new entry is inserted (FIFO eviction)

### Requirement: Logbook context injected into Pilot prompts

When Briefing, Copilot, or Autopilot generates a reply for a conversation whose contact has Logbook entries AND `account.pilot_logbook_enabled = true`, the resolved entries MUST be passed to the LLM as system-message context.

#### Scenario: Briefing includes Logbook
- **WHEN** `BriefingService` runs for a conversation whose contact has 3 Logbook entries
- **THEN** the LLM system prompt includes a "Known facts about this contact" section listing those 3 entries

#### Scenario: Logbook absent when feature disabled
- **WHEN** the same conversation is processed but `pilot_logbook_enabled = false`
- **THEN** the system prompt contains no Logbook content

### Requirement: Logbook viewer UI on contact page

The dashboard's contact detail view SHALL include a "Logbook" tab visible when `account.pilot_logbook_enabled = true`. The tab MUST list the contact's entries in reverse-chronological order, show source-message links, and allow agents to delete individual entries.

#### Scenario: Tab visible with feature on
- **WHEN** an agent opens a contact in an account with `pilot_logbook_enabled = true`
- **THEN** a "Logbook" tab appears in the contact detail panel

#### Scenario: Agent deletes an incorrect entry
- **WHEN** an agent clicks delete on a Logbook entry
- **THEN** a confirmation modal appears
- **AND** confirming destroys the entry via `DELETE /api/v2/accounts/:account_id/pilot/logbook_entries/:id`
- **AND** the entry disappears from the tab

#### Scenario: Source link navigates to message
- **WHEN** an agent clicks the source-message link on an entry
- **THEN** the dashboard navigates to that message in its original conversation
