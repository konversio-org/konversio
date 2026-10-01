## Capability: pilot-playground-run-report

A per-run execution report returned with the Pilot playground response: final handler attribution, an ordered log of tool and handoff events with sanitized arguments and truncated previews, a knowledge-attached flag, and run duration — displayed in the Playground UI.

---

## ADDED Requirements

### Requirement: run report in the playground response

When a playground run executes with a configuration object, the response SHALL include a run report alongside the existing reply and invoked tool names. The report MUST identify the handler that produced the final reply (assistant or scenario, including whether it is temporary and its display title), MUST list the run's events in execution order, MUST state whether temporary knowledge text was attached, and MUST include the run's wall-clock duration in milliseconds.

#### Scenario: reply handled by the assistant

- Given a run that never hands off
- When the response is rendered
- Then the report's handler identifies the assistant by its display name
- And the handler is not marked temporary

#### Scenario: reply handled by a temporary scenario

- Given a run that hands off to a temporary scenario which produces the final reply
- When the response is rendered
- Then the report's handler identifies the scenario by its draft title
- And the handler is marked temporary

#### Scenario: knowledge-attached flag reflects the run

- Given a run with knowledge text supplied
- When the response is rendered
- Then the report states that temporary knowledge was attached
- Given a run without knowledge text
- Then the report states that no temporary knowledge was attached

---

### Requirement: tool events with sanitized arguments and truncated previews

The report SHALL record each tool invocation as an event containing the tool's display name, its status, and its effective arguments. Tool events begin in a running state and transition to completed or failed when the tool finishes; failure MUST be recorded when the tool returns an error result. Result content MUST be included only as a bounded preview of at most 500 characters. Tool display names MUST strip internal namespace prefixes so testers see the tool they configured. needs investigation: the exact tool start/complete hooks available in the pinned ai-agents SDK version and their payloads (see design.md); if a hook is unavailable, the report MUST degrade to a partial event log rather than failing the run.

#### Scenario: successful tool call

- Given a run in which the assistant calls a documentation search tool
- When the tool completes successfully
- Then the report contains a tool event with the tool's display name, status completed, the effective arguments, and a result preview of at most 500 characters

#### Scenario: failed tool call

- Given a run in which a tool returns an error result
- When the run finishes
- Then the tool event's status is failed
- And the result preview contains the error content within the preview limit

#### Scenario: long results are truncated

- Given a tool whose result exceeds 500 characters
- When the report is rendered
- Then the result preview is truncated to the preview limit

---

### Requirement: handoff events

The report SHALL record each agent handoff as an event identifying the source handler, the target handler, and a bounded preview of the reason. Handler identities in handoff events MUST use the same human-readable descriptors as the report's final-handler attribution, including the temporary marker for temporary scenarios.

#### Scenario: assistant hands off to a temporary scenario

- Given a run that hands off from the assistant to a temporary scenario
- When the report is rendered
- Then a handoff event shows the assistant as the source and the temporary scenario as the target, marked temporary
- And the event includes a truncated reason preview

---

### Requirement: sanitization of sensitive values

Before any argument or preview is returned, the report SHALL redact credential material: values under keys whose names indicate credentials (including passwords, secrets, tokens, API keys, credentials, authorization headers, and cookies) MUST be masked recursively through nested objects and arrays, and credential-looking assignments embedded in strings — including HTTP-header-like lines and serialized JSON payloads — MUST be masked as well. Sanitization MUST be applied before truncation so redaction markers are never cut off mid-value.

#### Scenario: credential argument is masked

- Given a custom HTTP tool invoked with an argument whose key names a token
- When the report is rendered
- Then the argument value is masked in the tool event
- And non-credential sibling arguments remain visible

#### Scenario: nested structures are masked recursively

- Given tool arguments containing a nested object with a credential-named key at depth two
- When the report is rendered
- Then the nested credential value is masked

#### Scenario: credentials inside string payloads are masked

- Given a tool result string containing an authorization-header-like line
- When the report is rendered
- Then the credential portion of the line is masked in the preview
- And the non-credential remainder of the preview stays readable

---

### Requirement: run duration

The report SHALL include the run's elapsed wall-clock time in whole milliseconds, measured from the start of the playground run to the completion of the response.

#### Scenario: duration is recorded per run

- Given two consecutive playground runs
- When both responses are rendered
- Then each report carries its own non-negative duration in milliseconds

---

### Requirement: run report display in the Playground UI

The Playground UI SHALL render a collapsible run report beneath each assistant response produced by a configured run, showing the duration, the final handler with a visible marker for temporary scenarios, and the ordered event list with tool statuses, arguments, previews, and handoff details.

#### Scenario: report is collapsed by default

- Given a playground response with a run report
- When the response is displayed
- Then a summary line shows the run duration
- And the full event log is hidden until the tester expands it

#### Scenario: temporary handler is visually marked

- Given a run whose final handler is a temporary scenario
- When the tester expands the report
- Then the handler title carries a visible temporary marker
