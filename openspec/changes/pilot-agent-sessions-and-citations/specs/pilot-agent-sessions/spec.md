## Capability: pilot-agent-sessions

Durable per-run session records linking Pilot AI runs to the conversations (or copilot threads) they ran on and the messages they produced, with knowledge-usage attribution and turn-scoped run context.

---

## ADDED Requirements

### Requirement: pilot_agent_sessions table and Pilot::AgentSession model

The system SHALL provide a `pilot_agent_sessions` table and a `Pilot::AgentSession` model in the core tree that records one row per completed Pilot AI run. Each session MUST store: a session kind discriminator; a polymorphic subject reference; an optional polymorphic result reference; account, assistant, and optional user references; the model identifier used for the run; JSONB arrays of offered FAQ ids, used FAQ ids, consulted document ids, cited document ids, and participating scenario ids; and a JSONB run context.

#### Scenario: session kinds and their subject/result types

- Given the session model
- Then it supports an autopilot kind whose subject is a `Conversation` and whose result is a `Message`
- And it supports a copilot kind whose subject is the copilot thread and whose result is the copilot message

#### Scenario: querying sessions for reporting and lookup

- Given sessions exist for an account
- Then the table is indexed for account-scoped listing by kind and creation time
- And for lookup by subject and by result within an account
- And the JSONB id arrays for consulted documents, cited documents, and used FAQs are GIN-indexed for containment queries

#### Scenario: account is derived from the assistant

- Given a session built with an assistant but no explicit account
- When the session is validated
- Then its account equals the assistant's account

---

### Requirement: session integrity validations

A session MUST be internally consistent: subject and result types MUST match the session kind, and subject and result MUST belong to the session's account.

#### Scenario: mismatched subject type is rejected

- Given an autopilot-kind session whose subject is not a conversation
- When the session is validated
- Then validation fails on the subject type

#### Scenario: mismatched result type is rejected

- Given an autopilot-kind session whose result is not a message
- When the session is validated
- Then validation fails on the result type

#### Scenario: cross-account subject is rejected

- Given a session whose subject belongs to a different account than the assistant
- When the session is validated
- Then validation fails on the subject

#### Scenario: cross-account result is rejected

- Given a session whose result record belongs to a different account
- When the session is validated
- Then validation fails on the result

#### Scenario: result may be absent

- Given a session with no result reference
- When the session is validated
- Then result-related validations are skipped

---

### Requirement: post-delivery, failure-isolated capture

The autopilot reply pipeline SHALL record a session after a successful run has produced its customer-facing reply or handoff. Capture MUST happen after and outside message delivery, MUST skip runs that were not successful, and MUST never raise into the delivery path: any capture failure is logged and reported to the exception tracker while the delivered message stands.

#### Scenario: successful reply run is captured

- Given an autopilot run completes successfully and delivers an outgoing message
- When capture runs
- Then a session exists linking the assistant, the conversation as subject, and the delivered message as result
- And it records the model identifier used for the run

#### Scenario: handoff run links to the handoff note

- Given a run that ended in a handoff and recorded a private handoff note during the run
- When capture runs
- Then the session's result is that private note rather than the generic handoff message

#### Scenario: unsuccessful run is not captured

- Given a run that did not complete successfully
- When capture is invoked
- Then no session is created

#### Scenario: capture failure never breaks delivery

- Given the session creation raises an error
- When capture runs after a delivered reply
- Then the error is logged and reported to the exception tracker
- And the delivered message and conversation state are unaffected

---

### Requirement: knowledge-usage attribution

Each session SHALL record which knowledge the run was offered, actually used, cited to the customer, and which scenarios participated.

#### Scenario: offered and used FAQs recorded

- Given a run whose retrieval offered FAQs and whose reply drew on a subset
- When the session is captured
- Then offered FAQ ids and used FAQ ids are stored as separate arrays

#### Scenario: cited documents reflect delivered, eligible citations only

- Given a run with citations enabled whose delivered reply parts reference source indexes
- When the session is captured
- Then cited document ids contain exactly the documents behind indexes that were both used in the delivered parts and resolvable to eligible customer-visible URLs

#### Scenario: cited documents empty when citations disabled

- Given a run on an assistant whose citation config is disabled
- When the session is captured
- Then cited document ids is an empty array

#### Scenario: participating scenarios recorded and validated

- Given a run in which one or more scenario agents acted during the turn
- When the session is captured
- Then the scenario id array contains those scenarios' ids, deduplicated
- And any id not belonging to the assistant's own scenarios is excluded

---

### Requirement: turn-scoped run context

The session's run context SHALL contain the current turn only: the latest customer message and everything that followed it (assistant replies, tool calls and results, scenario hops), with any rich content objects normalized to a serializable form.

#### Scenario: context trimmed to the current turn

- Given a run whose full history spans several turns
- When the session is captured
- Then the stored run context begins at the latest customer message
- And contains no entries from earlier turns

#### Scenario: rich content is serialized

- Given a turn entry whose content is a rich (multimodal) content object
- When the session is captured
- Then the stored entry contains a plain serializable representation of that content

---

### Requirement: ownership and lifecycle

Accounts and Pilot assistants SHALL expose their sessions, and destroying an account or assistant MUST clean up its sessions asynchronously.

#### Scenario: assistant deletion removes sessions

- Given an assistant with recorded sessions
- When the assistant is destroyed
- Then its sessions are destroyed via the background cleanup path
