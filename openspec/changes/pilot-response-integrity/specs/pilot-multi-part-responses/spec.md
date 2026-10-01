## Capability: pilot-multi-part-responses

Pilot AI replies expressed as an ordered list of parts, each part carrying its customer-visible text and the numeric indexes of the knowledge sources it relies on. Plain-text replies degrade gracefully to a single citation-free part. Trusted-URL resolution and numbered-link rendering are owned by the `pilot-response-citations` capability (change `pilot-agent-sessions-and-citations`); this capability owns the runner output contract, normalization, and persistence.

---

## ADDED Requirements

### Requirement: structured runner output contract

When an assistant's citation config is enabled, the autopilot generation pipeline SHALL ask the model for a structured reply consisting of a reasoning field and an ordered list of at least one part. Each part SHALL carry a non-empty text field and a list of numeric source indexes (possibly empty). All customer-visible text MUST live inside part text fields; source indexes MUST refer only to indexes shown in knowledge results, and source URLs MUST NOT appear in reply text or citation fields.

#### Scenario: structured reply is produced when citations are enabled

- Given an assistant whose citation config is enabled
- When the autopilot run completes
- Then the runner output contains an ordered list of parts, each with text and source indexes

#### Scenario: reply format unchanged when citations are disabled

- Given an assistant whose citation config is disabled
- When the autopilot run completes
- Then the reply is produced as today (plain text), with no citation instructions in the prompt

---

### Requirement: parsing and normalization

The system SHALL parse any model output into the structured form, keeping part order, trimming part text, dropping non-text or blank parts, and normalizing source indexes to deduplicated positive integers. Output that is plain text or otherwise not structured SHALL degrade to a single part with no source indexes.

#### Scenario: well-formed output parses in order

- Given a model output with three parts in order
- When the reply is parsed
- Then the parts list preserves the three texts in order
- And each part's indexes are positive integers with duplicates removed

#### Scenario: malformed parts are excluded

- Given an output whose parts list contains an entry with blank text and an entry that is not a text part
- When the reply is parsed
- Then those entries are not present in the resulting parts list

#### Scenario: invalid indexes are discarded

- Given a part whose indexes include zero, negative, and non-numeric values
- When the reply is parsed
- Then only the positive integer indexes survive

#### Scenario: plain string degrades to one part

- Given a model output that is a plain string
- When the reply is parsed
- Then the result is exactly one part containing that text with an empty index list

---

### Requirement: assembled plain text and sentinel safety

The system SHALL join part texts with a blank line to form the reply's plain-text form. Handoff and resolution sentinel parsing SHALL run on the assembled plain text (not on individual parts), and sentinel tokens MUST be stripped so they never appear in delivered part text.

#### Scenario: parts join into plain text

- Given a parsed reply with two parts
- When plain text is assembled
- Then the two texts are separated by exactly one blank line

#### Scenario: sentinels do not leak into delivered text

- Given a reply whose assembled plain text ends with a handoff or resolution sentinel
- When the customer message is built
- Then the sentinel token does not appear in any delivered part text

- needs investigation: the exact point where sentinel stripping happens once replies are structured (during parsing vs during message assembly) must be settled during implementation.

---

### Requirement: parts persisted on the delivered message

The outgoing AI message SHALL carry the structured parts (texts and source indexes, in order) in its additional attributes so the generation path can be inspected after delivery. Replies that degraded to a single plain part SHALL store exactly that one part.

#### Scenario: structured reply stores all parts

- Given an autopilot reply built from three parts
- When the outgoing message is created
- Then the message's additional attributes contain the three parts in order with their source indexes

#### Scenario: degraded reply stores one part

- Given a reply that degraded to a single citation-free part
- When the outgoing message is created
- Then the stored parts list contains exactly one part with an empty index list
