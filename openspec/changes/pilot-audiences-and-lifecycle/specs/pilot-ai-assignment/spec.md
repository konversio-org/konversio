## Capability: pilot-ai-assignment

Polymorphic AI assignee on conversations: automatic assignment of the engaged Pilot assistant, correct clearing on handoff and human assignment, and opt-in AI entries in the assignable-agents API.

---

## ADDED Requirements

### Requirement: Polymorphic AI assignee on conversations

Conversations SHALL support an AI assignee that is either an `AgentBot` or a `Pilot::Assistant`, stored on the existing `assignee_agent_bot_id` column discriminated by a new nullable `ai_assignee_type` column. A NULL type with a present id MUST read as the legacy `AgentBot` case. A conversation SHALL have at most one owner at a time: setting an AI assignee clears the human assignee, and setting a human assignee clears the AI assignee. The conversation's effective-assignee fallback and `unassigned` / `assigned` scopes MUST treat the AI assignee as an assignee.

#### Scenario: AI assignee and human assignee are mutually exclusive

- Given a conversation assigned to a human agent
- When a Pilot assistant is set as its AI assignee
- Then the human assignee is cleared

#### Scenario: unassigned scope excludes AI-held conversations

- Given a conversation whose only assignee is a Pilot assistant
- When conversations are filtered by the unassigned scope
- Then the conversation is not included

#### Scenario: legacy agent-bot rows still resolve

- Given a conversation with `assignee_agent_bot_id` set and `ai_assignee_type` NULL
- When the AI assignee is read
- Then it resolves to the corresponding `AgentBot`

---

### Requirement: Automatic assignment of the engaged assistant

When a conversation's initial status is determined and the inbox's Pilot assistant engages (audience and schedule both pass), and no human assignee is present, the assistant SHALL be recorded as the conversation's AI assignee. A non-engaging assistant MUST NOT be recorded.

#### Scenario: engaged assistant becomes AI assignee

- Given a web widget inbox with an attached assistant that engages the contact
- When a new conversation is created
- Then the assistant is the conversation's AI assignee and the status is `pending`

#### Scenario: non-engaging assistant is not assigned

- Given an assistant whose response window excludes the current time
- When a new conversation is created
- Then the conversation has no AI assignee and starts `open`

---

### Requirement: Clearing semantics on handoff and human assignment

Handing a conversation off to humans (`bot_handoff!`) SHALL clear the AI assignee. Assigning a human agent to a conversation that has an AI assignee SHALL clear the AI assignee, open the conversation if it was `pending`, and stamp `waiting_since` when blank. Assigning an AI assignee to a conversation SHALL clear the human assignee and set the status to `pending`. All such transitions MUST be performed under a row lock.

#### Scenario: handoff clears the AI assignee

- Given a `pending` conversation assigned to a Pilot assistant
- When the conversation is handed off
- Then the AI assignee is cleared and the status becomes `open`

#### Scenario: human takeover reopens the conversation

- Given a `pending` conversation assigned to a Pilot assistant
- When a human agent is assigned
- Then the AI assignee is cleared, the status becomes `open`, and `waiting_since` is set

#### Scenario: AI assignment clears the human assignee

- Given an `open` conversation assigned to a human agent
- When a Pilot assistant is assigned via the assignment API
- Then the human assignee is cleared and the status becomes `pending`

---

### Requirement: Opt-in AI assignees in the assignable-agents API

The assignable-agents endpoint SHALL include the account's Pilot assistants (and agent bots) in its payload only when the client explicitly opts in with an `include_ai_assignees` parameter. AI entries MUST carry a type discriminator distinguishing them from human users. Without the parameter the payload MUST remain unchanged for backward compatibility.

#### Scenario: default payload contains only humans

- Given an account with Pilot assistants
- When assignable agents are fetched without the opt-in parameter
- Then the payload contains only human agents and administrators

#### Scenario: opt-in payload includes assistants with discriminator

- Given an account with a Pilot assistant named "Mira"
- When assignable agents are fetched with `include_ai_assignees`
- Then the payload includes an entry for "Mira" with a type discriminator identifying it as an AI assignee
