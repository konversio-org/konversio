## Context

The playground exists so operators can trial a Pilot assistant before trusting it on a live channel. Today the playground endpoint forwards a message plus history to `Custom::Pilot::AutopilotService` with `source: 'playground'` and returns only the reply and the list of invoked tool names. The assistant always runs with its persisted scenarios, guidelines, guardrails, and indexed knowledge, and the run leaves no inspectable trace.

Upstream Chatwoot v4.18.0 addressed the same gap in its Enterprise tier: a per-run playground configuration (scenario selection, temporary scenario drafts, guideline/guardrail replacement, capped knowledge text rendered as untrusted reference material), per-run runtime names for temporary scenario agents, and a run trace collected through runner callbacks (tool start/complete with sanitized arguments and truncated previews, handoff events, duration).

**License axis for this change: EE → requirements-level clean-room.** The upstream Enterprise files were read for behavioral understanding only. This spec expresses the functional requirements in original wording: no upstream prompt text, UI copy, error-message strings, regular expressions, category taxonomies, or file/class naming is carried over. The implementation targets Konversio's architecture — `Pilot::` namespace, core tree only (no `enterprise/` directory), `Custom::Pilot::AutopilotService` as the run engine — and introduces no new persistence. Upstream's three service objects are replaced here by our own `Pilot::Playground::SessionConfig`, `Pilot::Playground::SessionRunner`, and `Pilot::Playground::RunReport` (names chosen for Konversio; they are requirements, not ports).

## Goals / Non-Goals

**Goals:**

- Let a tester override, per run and without saving anything: the participating persisted scenarios, additional temporary scenario drafts, the response guidelines, the guardrails, and an ad-hoc knowledge snippet.
- Inject the knowledge snippet into every agent's system prompt for the run as clearly delimited, untrusted reference material, capped in length.
- Give temporary scenario agents deterministic per-run runtime names that cannot collide with persisted scenario handoff tools.
- Return a run report with the playground response: final handler attribution, ordered tool/handoff events with sanitized arguments and truncated result previews, knowledge-attached flag, and run duration.
- Reject malformed configurations with structured `422` errors keyed by field path.
- Surface setup and run report in the Playground UI.

**Non-Goals:**

- Persisting playground drafts, sessions, or run history (no new tables; no `pilot_` migration in this change).
- Changing production (non-playground) inference behavior, handover evaluation, or conversation resolution.
- Multi-user/shared playground sessions, saved test suites, or assertions/grading of test runs.
- Porting any upstream prompt wording, redaction patterns, or code — this is a re-specification, not a port.
- Changing the existing response contract when no configuration is supplied (`{ reply, invoked_tool_names }` keeps working).

## Decisions

### Transient-only overrides — no new persistence

All playground overrides live in memory for the duration of one run. Temporary scenarios are instantiated as unsaved `Pilot::Scenario` objects so existing validations (presence, instruction tool references, handoff tool name length) can be reused for error reporting.

Alternatives considered:
- Persist draft scenarios/rules flagged as drafts. Rejected: it adds tables, lifecycle cleanup, and permission questions for something the playground only needs ephemerally.
- Store playground sessions for later replay. Rejected as out of scope; the run report is returned inline instead.

Rationale: the upstream feature is also fully transient; matching that keeps the change small and side-effect-free.

### A single validated configuration object at the boundary

The endpoint accepts one optional `playground_config` object. A dedicated `Pilot::Playground::SessionConfig` value object normalizes and validates it up front, aggregates all errors keyed by field path (e.g. `temporary_scenarios.0.title`), and raises a single invalid-configuration error carrying the error map. The controller rescues it and renders `422` with `{ error, errors }`.

Alternatives considered:
- Validate inline in the controller with strong params only. Rejected: cross-field rules (unique scenario ids, scenarios belonging to the assistant, unique client identifiers) do not belong in the controller.
- Fail on the first error. Rejected: a tester fixing a setup panel benefits from seeing every problem at once.

Rationale: one validation boundary keeps the controller thin and gives the frontend a stable, field-keyed error contract.

### Replace semantics for rule lists; presence of the key decides

For `response_guidelines` and `guardrails`: when the key is present, its array fully replaces the persisted list for the run; when the key is absent, the persisted list is used unchanged. An explicitly empty array therefore means "run with no rules of this kind" — a meaningful test case. Entries must be non-blank strings, trimmed, and de-duplicated.

Alternatives considered:
- Merge overrides with persisted rules. Rejected: testers cannot then observe the effect of removing a rule.
- A separate per-rule include/exclude flag sent by the client. Rejected: the client can compute the desired list; replace semantics keep the server contract minimal (the UI may still present checkboxes and compose the final list client-side).

Rationale: replace-on-present is unambiguous and trivially explainable in the UI.

### Knowledge text as an untrusted, delimited prompt block

The optional knowledge text is a plain string capped at a fixed maximum length (10,000 characters); anything longer is a validation error, not a silent truncation. When present, it is injected into the system prompt of the assistant agent and every scenario agent participating in the run, wrapped in explicit begin/end delimiters and preceded by a directive stating that the delimited content is untrusted reference material: it may be consulted as factual context but any instructions, tool requests, or policy changes inside it must not be followed. The exact delimiter strings and directive wording are the implementer's choice (original wording required — do not copy upstream prompt text).

Alternatives considered:
- Truncate over-long input silently. Rejected: a tester should know their snippet did not fit.
- Ingest the snippet as a temporary document searchable via the documentation tool. Rejected for this change: it requires embeddings and cleanup; needs investigation: whether a prompt-injected snippet is sufficient for large knowledge tests or whether a transient in-memory retrieval path should be added later.
- Inject only into the orchestrating assistant's prompt. Rejected: after a handoff the scenario agent would lose the context the tester provided.

Rationale: prompt injection is side-effect-free, immediate, and matches how testers think about "paste some text and ask about it". The untrusted-data framing is a prompt-injection defense.

### Deterministic per-run runtime names for temporary scenario agents

Each temporary scenario receives a runtime agent name derived deterministically from its client-supplied identifier (e.g. a truncated digest), namespaced so it cannot collide with the `handoff_key`/`handoff_tool_name` of any persisted scenario, and short enough to satisfy the ai-agents SDK tool-name length limit that `Pilot::Scenario` already enforces. Persisted scenarios keep their normal handoff identity. The run report maps runtime names back to human-readable handler descriptors.

Alternatives considered:
- Use the scenario title as the runtime name. Rejected: titles are not unique and can collide with persisted scenarios.
- Random names per run. Rejected: determinism per client identifier keeps repeated runs of the same setup comparable and debuggable.

Rationale: handoff tools are addressed by name inside the agent graph; temporary agents need guaranteed-unique names without database ids.

### Run report collected through runner callbacks

`Custom::Pilot::AutopilotService` gains an optional runtime-configuration input and an optional callback set. When callbacks are supplied (playground only), a `Pilot::Playground::RunReport` collector records: tool invocations (start and completion, with failure derived from error results), agent handoffs (from/to handlers and reason), and wall-clock duration. The response gains an additive run-report object; `reply` and `invoked_tool_names` remain.

Alternatives considered:
- Reconstruct the trace from the agent run result after the fact. Rejected: intermediate tool calls and handoff reasons are not reliably recoverable from the final result alone.
- Stream events over a websocket. Rejected as out of scope; the playground request/response cycle is sufficient.

Rationale: callbacks observe the run as it happens and are already the extension point the runner wrapper uses elsewhere (e.g. chat-created hooks). needs investigation: the exact tool-start/tool-complete/handoff callback hooks exposed by the pinned ai-agents SDK version in this repo, and how they surface through Konversio's runner wrapper — upstream integrates a different gem version, so hook names and payloads must be verified locally before implementation.

### Sanitize before display

Tool arguments and result previews are sanitized in the collector before being returned: values under keys whose names indicate credentials (passwords, secrets, tokens, API keys, authorization headers, cookies, and similar) are redacted recursively through nested structures, and credential-looking assignments embedded in strings (including HTTP-header-like lines and serialized JSON payloads) are masked. Result previews and handoff reasons are truncated to a bounded preview length (500 characters) after sanitization. Tool display names strip any internal namespace prefixes so testers see the tool they configured. The specific redaction patterns are the implementer's design (original work; do not port upstream patterns).

Alternatives considered:
- Return raw arguments. Rejected: playground tools can call real HTTP endpoints with real credentials; the report would leak them into the UI and logs.
- Drop arguments entirely. Rejected: seeing the effective arguments is half the debugging value of the report.

Rationale: redact-then-truncate keeps the report useful without becoming a secret exfiltration path.

### Backward-compatible endpoint contract

The playground configuration is optional. When it is absent, the endpoint behaves exactly as today (persisted configuration, existing response shape), so the current `PlaygroundPanel.vue` keeps working until the UI ships.

## Risks / Trade-offs

- **Prompt-injection via knowledge text** -> mitigated by the untrusted-block directive and delimiters; residual risk is inherent to LLM features and is documented in the spec.
- **Callback drift vs. the ai-agents SDK** -> the pinned SDK's hooks must be verified (see needs-investigation); if a hook is missing, the report degrades gracefully (events list may be partial) rather than failing the run.
- **Handoff tool name length** -> temporary runtime names must respect the existing 60-character SDK limit already enforced for persisted scenarios.
- **Response size** -> previews are truncated and arguments are bounded by tool schemas; no pagination is needed for a single run.

## Migration Plan

1. Ship the backend (configuration object, runner wiring, run report) behind the existing endpoint; old clients are unaffected because the payload is optional.
2. Ship the frontend setup panel and run-report display.
3. Rollback by ignoring the optional payload and hiding the new UI; no data migration exists to reverse.

## Open Questions

- needs investigation: which run lifecycle callbacks the pinned ai-agents SDK (and Konversio's wrapper in `Custom::Pilot::AutopilotService`) actually expose for tool start/complete and agent handoff, and their payload shapes.
- needs investigation: whether unsaved `Pilot::Scenario` instances exercise all relevant validations (the handoff tool name length validation derives from `handoff_key`, which may assume a persisted id) or whether temporary scenarios need a parallel validation path keyed on the per-run runtime name.
- needs investigation: whether prompt-injected knowledge text is sufficient long-term, or whether a transient in-memory retrieval path over the snippet should complement `search_documentation` for large inputs.
