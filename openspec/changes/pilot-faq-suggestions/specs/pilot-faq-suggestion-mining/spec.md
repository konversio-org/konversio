## Capability: pilot-faq-suggestion-mining

Resolve-time FAQ candidates are staged as deduplicated, source-counted `Pilot::FaqSuggestion` records with per-conversation `Pilot::FaqObservation` evidence, instead of being written directly into the assistant's knowledge base.

---

## ADDED Requirements

### Requirement: FAQ suggestion records

The system SHALL store mined FAQ candidates as `Pilot::FaqSuggestion` records scoped to an assistant and an account, each carrying a question, an answer, a normalized language code, a source count of contributing conversations, a lifecycle status of `open`, `approved`, or `dismissed` (default `open`), and a vector embedding of the question/answer text used for similarity matching.

#### Scenario: new candidate creates an open suggestion

- Given an assistant with FAQ mining enabled
- When a mined candidate matches no approved knowledge entry, no dismissed suggestion, and no open suggestion in the candidate's language
- Then a new `Pilot::FaqSuggestion` is created with status `open`, the candidate's question and answer, the conversation's normalized language, and a source count reflecting the first sighting

#### Scenario: suggestion embedding is maintained while open

- Given an open suggestion whose question or answer changes
- When the record is saved
- Then its embedding is refreshed asynchronously from the updated question/answer text
- And a suggestion that is no longer open does not schedule further embedding refreshes

#### Scenario: suggestions are ordered by evidence

- When suggestions are listed
- Then they are ordered by descending source count, then by most recently updated

---

### Requirement: per-conversation observations

The system SHALL record every mined candidate as a `Pilot::FaqObservation` tied to its source conversation, storing the question and answer as generated for that conversation. An observation is either attached to a suggestion or discarded (matched existing knowledge or a dismissed suggestion). A conversation MUST contribute at most one attached observation per suggestion.

#### Scenario: first sighting attaches an observation

- Given a newly created suggestion for a mined candidate
- Then an attached observation links the suggestion to the source conversation with the generated question, answer, and language

#### Scenario: repeat sighting increments source count instead of duplicating

- Given an open suggestion in language `en`
- When a different resolved conversation yields a candidate judged the same FAQ
- Then a new attached observation is created for that conversation
- And the suggestion's source count is incremented
- And no new suggestion is created

#### Scenario: same conversation does not double-count

- Given a suggestion that already has an attached observation from conversation C
- When mining of conversation C is retried and produces the same candidate
- Then no additional observation is created
- And the source count is unchanged

#### Scenario: discarded sightings leave an audit trail

- Given a mined candidate that matches an approved knowledge entry or a dismissed suggestion
- Then a discarded observation is recorded for the source conversation
- And no suggestion is created or modified

---

### Requirement: two-stage candidate matching

Candidate routing MUST be decided by a two-stage match: first an embedding shortlist (nearest neighbors under cosine distance 0.3 over the candidate's `"<question>: <answer>"` embedding, limited to a small fixed number of records per pool), then a per-record LLM equivalence judgment returning a strict boolean verdict on whether the pair is the same FAQ. Matching pools are consulted in order: approved knowledge entries, then dismissed suggestions in the candidate's language, then open suggestions in the candidate's language.

#### Scenario: match against approved knowledge suppresses the candidate

- Given an approved `Pilot::AssistantResponse` covering the same FAQ
- When a mined candidate is routed
- Then the candidate is discarded without creating a suggestion

#### Scenario: match against a dismissed suggestion is sticky

- Given a dismissed suggestion in the candidate's language covering the same FAQ
- When a mined candidate is routed
- Then the candidate is discarded
- And future sightings of the same FAQ continue to be discarded

#### Scenario: embedding shortlist alone is not sufficient to match

- Given a shortlisted record within the distance threshold
- When the equivalence judgment returns false
- Then the candidate is treated as unmatched for that pool and routing continues

#### Scenario: judgment failure is not silently treated as a mismatch

- Given a shortlisted record
- When the equivalence judgment call fails (unparseable response, non-boolean verdict, or LLM error)
- Then the failure is raised so the mining job retries
- And no suggestion or observation is created from the failed comparison

#### Scenario: matching is language-scoped for suggestions

- Given an open suggestion in language `en`
- When a candidate in language `de` is routed
- Then the `en` suggestion is not considered a match
- And a new suggestion in `de` may be created

---

### Requirement: conversation-level mining prerequisites

Mining of a resolved conversation MUST short-circuit before any LLM call when the conversation has no human support reply, and MUST only feed customer and human-agent messages (never bot or assistant output) into candidate generation.

#### Scenario: bot-only conversation produces nothing

- Given a resolved conversation with no human agent reply
- When the mining job runs
- Then no candidates are generated and no records are created

#### Scenario: generation sources answers only from human agents

- Given the candidate generation step
- Then the generation contract MUST require that answer content originates from human support agent statements only, that customer messages cannot supply answer facts, that only durable and publicly reusable knowledge qualifies, and that private or customer-specific details are excluded
- And when nothing qualifies, generation returns an empty result

---

### Requirement: concurrent-safety of attach

Attaching an observation to an existing open suggestion MUST be performed under a row lock, MUST re-verify the suggestion is still open, and MUST re-verify the suggestion's question/answer have not changed since the match was computed; a failed re-verification re-routes the candidate instead of attaching.

#### Scenario: suggestion decided between match and attach

- Given a candidate matched to an open suggestion
- When the suggestion is approved or dismissed before the attach completes
- Then the attach does not proceed and the candidate is re-routed

#### Scenario: suggestion edited between match and attach

- Given a candidate matched to an open suggestion
- When the suggestion's question or answer changed after the match
- Then the attach does not proceed and the candidate is re-routed
