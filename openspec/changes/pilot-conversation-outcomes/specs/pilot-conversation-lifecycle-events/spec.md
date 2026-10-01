## Capability: pilot-conversation-lifecycle-events

Domain events on the internal event bus describing Pilot conversation state transitions. These events decouple outcome recording (and future consumers such as reporting and webhooks) from the customer-facing flows that trigger them.

---

## ADDED Requirements

### Requirement: Handoff lifecycle event

Whenever a Pilot-handled conversation is transferred to human handling, the system SHALL emit a handoff lifecycle event on the internal event bus. The event payload SHALL carry the conversation, the attributed Pilot assistant, the handoff's source (which path triggered it), the categorized handoff reason, and the event timestamp. Every handoff path MUST emit the event: AI-tool-initiated escalation, inference-driven handoff, inactivity- or time-based handoff, and quota/usage-limit-driven handoff.

#### Scenario: tool-initiated handoff emits the event

- Given a conversation where the AI invokes its escalation mechanism
- When the handoff is executed
- Then a handoff lifecycle event is emitted with the conversation, assistant, a source identifying the AI-initiated path, and the categorized reason the AI supplied

#### Scenario: quota-driven handoff emits the event

- Given a conversation handed off because AI usage quota was exhausted
- When the handoff is executed
- Then a handoff lifecycle event is emitted with a source identifying the system path and the quota-denoting reason category

#### Scenario: outcome listener consumes the event

- Given a handoff lifecycle event is emitted
- When the outcome listener processes it
- Then the handoff timestamp and reason category are recorded on the covering episode

---

### Requirement: Resolution lifecycle event

When a Pilot-involved conversation is resolved, the system SHALL support a resolution lifecycle signal consumable by outcome recording. Reusing the core conversation-resolved event for this purpose is acceptable.

#### Scenario: resolution is observable by outcome recording

- Given a conversation with an open episode
- When the conversation is resolved
- Then outcome recording observes the transition and records the resolution timestamp on the covering episode

---

### Requirement: Event dispatch is failure-isolated

Lifecycle event emission SHALL be a secondary effect of the customer-facing flow: a dispatch failure MUST be logged and reported to the exception tracker, and MUST NOT alter the flow that triggered it (an escalation MUST still complete, a resolution MUST still succeed).

#### Scenario: dispatch failure does not block handoff

- Given event dispatch will raise an error
- When a Pilot handoff is executed
- Then the conversation is transferred to human handling normally
- And the dispatch error is logged and reported to the exception tracker
