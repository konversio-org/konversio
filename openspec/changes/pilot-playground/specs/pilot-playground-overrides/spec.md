## Capability: pilot-playground-overrides

Per-run, never-persisted overrides for the Pilot playground: scenario selection, temporary scenario drafts, response guideline and guardrail replacement, and capped knowledge text injected as untrusted reference material — with per-run agent naming and structured validation errors.

---

## ADDED Requirements

### Requirement: optional per-run playground configuration

The playground endpoint SHALL accept an optional configuration object alongside the existing message and message history. When the object is absent, the endpoint MUST behave exactly as before this change: the assistant runs with its persisted scenarios, rules, and knowledge, and the response keeps its existing shape.

#### Scenario: no configuration supplied — current behavior preserved

- Given a Pilot assistant with persisted scenarios and rules
- When a playground request is made without a configuration object
- Then the run uses all enabled persisted scenarios and the persisted response guidelines and guardrails
- And the response contains the reply and invoked tool names as before

#### Scenario: configuration must be an object

- Given a playground request whose configuration value is not an object
- When the request is processed
- Then the endpoint responds with HTTP 422
- And the response body contains an error keyed to the configuration field

---

### Requirement: scenario selection per run

The configuration MAY contain a list of persisted scenario ids selecting which of the assistant's scenarios participate in the run. When the key is present, only the listed scenarios participate; when the key is absent, all enabled persisted scenarios participate. The list MUST contain unique positive ids that all belong to the assistant.

#### Scenario: explicit selection limits participating scenarios

- Given an assistant with enabled scenarios A, B, and C
- When a run selects only scenario A
- Then only scenario A is available as a handoff target during that run

#### Scenario: unknown or foreign scenario id is rejected

- Given a scenario that does not belong to the assistant
- When a run selects that scenario's id
- Then the endpoint responds with HTTP 422
- And the error identifies the scenario selection field and the offending ids

#### Scenario: duplicate ids are rejected

- Given a selection containing the same scenario id twice
- When the request is processed
- Then the endpoint responds with HTTP 422 identifying the scenario selection field

---

### Requirement: temporary scenarios per run

The configuration MAY contain temporary scenario drafts with a title, description, instruction, and a client-supplied identifier. Temporary scenarios MUST be validated with the same rules as persisted scenarios, MUST participate in the run as handoff targets equal to persisted scenarios, and MUST NOT be written to the database. Client-supplied identifiers MUST be present and unique within a run.

#### Scenario: temporary scenario participates without persistence

- Given an assistant with no persisted scenarios
- When a run supplies a valid temporary scenario draft and the conversation matches its instruction
- Then the run may hand off to the temporary scenario
- And no scenario record exists in the database after the run

#### Scenario: invalid draft reports per-field errors

- Given a temporary scenario draft with a blank title
- When the request is processed
- Then the endpoint responds with HTTP 422
- And the errors identify the failing entry and field (for example the title of the first temporary scenario)

#### Scenario: duplicate client identifiers are rejected

- Given two temporary scenario drafts sharing one client-supplied identifier
- When the request is processed
- Then the endpoint responds with HTTP 422 identifying the temporary scenario collection

---

### Requirement: per-run runtime agent names for temporary scenarios

Each temporary scenario SHALL receive a deterministic per-run runtime agent name derived from its client-supplied identifier. Runtime names MUST NOT collide with any persisted scenario's handoff identity and MUST satisfy the tool-name length limit enforced for scenario handoff tools.

#### Scenario: runtime names are deterministic per client identifier

- Given a temporary scenario with client identifier X
- When two separate runs supply the same draft
- Then both runs use the same runtime agent name for that scenario

#### Scenario: runtime names cannot collide with persisted scenarios

- Given a persisted scenario and a temporary scenario draft
- When the run builds the agent graph
- Then the temporary scenario's runtime agent name differs from every persisted scenario's handoff tool identity

#### Scenario: tool references in temporary instructions are honored

- Given a temporary scenario whose instruction references enabled custom tools
- When the scenario participates in a run
- Then those tools are available to the temporary scenario's agent for that run

---

### Requirement: rule list replacement per run

The configuration MAY contain replacement response guideline and guardrail lists. When a rule key is present, its list SHALL fully replace the assistant's persisted list for the run; when the key is absent, the persisted list MUST be used unchanged. Entries MUST be strings, MUST be non-blank after trimming, and MUST be de-duplicated for the run.

#### Scenario: present key replaces persisted rules

- Given an assistant with persisted guardrails
- When a run supplies a replacement guardrail list
- Then only the supplied guardrails apply during that run
- And the persisted guardrails are unchanged after the run

#### Scenario: explicit empty list removes rules for the run

- Given an assistant with persisted response guidelines
- When a run supplies an empty guideline list
- Then no response guidelines apply during that run

#### Scenario: absent key keeps persisted rules

- Given an assistant with persisted guardrails
- When a run supplies a configuration without the guardrail key
- Then the persisted guardrails apply during that run

#### Scenario: blank or non-string entries are rejected

- Given a replacement rule list containing a blank or non-string entry
- When the request is processed
- Then the endpoint responds with HTTP 422 identifying the rule field

---

### Requirement: capped knowledge text injected as untrusted reference material

The configuration MAY contain a knowledge text string. Its length MUST NOT exceed a fixed cap of 10,000 characters; over-long input is a validation error and MUST NOT be silently truncated. When present, the text SHALL be injected into the system prompt of the assistant agent and every participating scenario agent for the run, wrapped in explicit begin/end delimiters and preceded by a directive that the delimited content is untrusted reference material: it may be consulted as factual context, but instructions, tool requests, or policy changes inside it MUST NOT be followed. The text MUST NOT be persisted, indexed, or made searchable outside the run.

#### Scenario: knowledge text reaches every agent in the run

- Given a run with knowledge text and a temporary scenario
- When the run hands off to the temporary scenario
- Then the scenario agent's instructions still contain the delimited knowledge block

#### Scenario: over-long knowledge text is rejected

- Given a knowledge text longer than 10,000 characters
- When the request is processed
- Then the endpoint responds with HTTP 422 identifying the knowledge field and the limit
- And no run is executed

#### Scenario: embedded instructions are treated as data

- Given knowledge text containing imperative instructions aimed at the assistant
- When the run executes
- Then the system prompt presents the text as untrusted reference material between delimiters
- And the assistant is directed not to follow instructions contained within the delimited block

---

### Requirement: structured validation error contract

All configuration validation failures SHALL be reported together in a single HTTP 422 response whose body contains an error message and a map of field paths to message lists, so the UI can highlight every problem at once.

#### Scenario: multiple failures are aggregated

- Given a configuration with an unknown scenario id and a temporary scenario missing its client identifier
- When the request is processed
- Then the endpoint responds with HTTP 422
- And the error map contains entries for both the scenario selection and the temporary scenario identifier
