## Capability: pilot-response-citations

Structured Pilot replies whose parts cite knowledge sources by index, resolved server-side to trusted customer-visible URLs and rendered as numbered links in the customer-facing message. Source URLs always come from server-side knowledge records, never from model output.

---

## ADDED Requirements

### Requirement: structured reply parts

When an assistant's citation config is enabled, the generation pipeline SHALL ask the model for a reply expressed as an ordered list of parts, each part carrying its text and the numeric indexes of the knowledge results it relies on. The system SHALL parse any model response into this structured form, degrading gracefully to a single citation-free part when the response is plain text or otherwise unstructured.

#### Scenario: structured response parses into parts

- Given a model response containing an ordered list of parts with text and citation indexes
- When the reply is parsed
- Then each part's text is preserved in order
- And citation indexes are kept as positive integers, deduplicated per part

#### Scenario: malformed parts are dropped

- Given a response whose parts include non-text entries or blank text
- When the reply is parsed
- Then those entries are excluded from the parts list

#### Scenario: plain-text response degrades to one part

- Given a model response that is a plain string (citations disabled or model ignored the structure)
- When the reply is parsed
- Then the result is a single part containing that text with no citation indexes

#### Scenario: prompt instructs indexed citations only when enabled

- Given an assistant whose citation config is enabled
- When the generation prompt is assembled
- Then the model is instructed to attach source indexes per reply part using only indexes shown in knowledge results
- And the model is forbidden from placing source URLs in reply text or citation fields

#### Scenario: prompt unchanged when citations disabled

- Given an assistant whose citation config is disabled
- When the generation prompt is assembled
- Then no citation instructions are added and the response format is unchanged

---

### Requirement: trusted customer-visible citation URLs

The system SHALL resolve cited indexes to source URLs entirely on the server, using the run's index→document mapping and the knowledge documents behind it. A URL is eligible only when its document is flagged customer-visible, the link is a well-formed `http(s)` URI, and the link does not point at an uploaded PDF (uploaded files have no customer-resolvable external link).

#### Scenario: eligible document yields its URL

- Given a cited index mapped to a customer-visible document with a valid `https` external link
- When trusted citation URLs are resolved
- Then the index maps to that URL

#### Scenario: non-visible or ineligible sources yield no URL

- Given cited indexes mapped to documents that are not customer-visible, have malformed links, or are uploaded PDFs
- When trusted citation URLs are resolved
- Then those indexes map to no URL

#### Scenario: resolution gated on citation config

- Given an assistant whose citation config is disabled
- When trusted citation URLs are resolved for a run
- Then the result is empty regardless of run state

---

### Requirement: customer message rendering with numbered links

The customer-facing message content SHALL be assembled from the reply parts, appending each part's citations as numbered markdown links. Display numbers MUST be assigned per unique URL in first-appearance order and reused on repeats; URLs MUST be markdown-escaped; and links MUST be placed on a new line when the part's text ends with a code fence. Indexes without an eligible URL MUST be silently dropped. The assembled content MUST be non-blank to be delivered.

#### Scenario: citations render as numbered links

- Given a two-part reply where part one cites one eligible source and part two cites that source plus a second one
- When customer content is assembled
- Then part one's text is followed by a `[1](url)` link
- And part two reuses number 1 for the repeated URL and number 2 for the new URL

#### Scenario: link placement after a code fence

- Given a part whose text ends with a closing code fence and which cites an eligible source
- When customer content is assembled
- Then the citation link appears on a new line after the fence, not inline with it

#### Scenario: ineligible citations are dropped silently

- Given a part citing an index with no eligible URL
- When customer content is assembled
- Then the part's text is delivered without any link for that index

#### Scenario: citation-free variant available

- Given a parsed structured reply
- When a citation-stripped copy is requested
- Then the copy contains the same texts with all citation indexes emptied

---

### Requirement: reply parts persisted on the message

The outgoing AI message SHALL carry its structured reply parts in its additional attributes so the generation path can be inspected after delivery.

#### Scenario: parts stored on the delivered message

- Given an autopilot reply built from structured parts
- When the outgoing message is created
- Then the message's additional attributes contain the ordered parts with their citation indexes
- And the message sender is the assistant

#### Scenario: plain replies store a single part

- Given a reply that degraded to a single citation-free part
- When the outgoing message is created
- Then the stored parts contain exactly that one part

---

### Requirement: coexistence with the legacy citation toggle

The structured citation mechanism MUST NOT conflict with the assistant's existing `citation_behavior` toggle that governs `Source:` line surfacing in the documentation-search tool. For messages delivered from structured replies, link rendering MUST be owned by the structured-parts mechanism so sources are not surfaced twice.

#### Scenario: no duplicate source surfacing

- Given an assistant with both the legacy toggle on and structured citations enabled
- When a reply cites a source that the documentation-search tool also surfaced inline
- Then the delivered customer message does not present the same source twice in conflicting forms

- needs investigation: the exact interaction between the legacy `Source:` line behavior and structured replies (suppress tool-level source lines when structured citations are active, or keep both) must be settled during implementation.
