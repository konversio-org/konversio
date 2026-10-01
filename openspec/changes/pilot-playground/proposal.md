## Why

Konversio's Pilot playground (`Api::V1::Accounts::Pilot::AssistantsController#playground`, backed by `Custom::Pilot::AutopilotService` with `source: 'playground'`) currently runs the assistant exactly as it is persisted. An operator who wants to try a draft scenario, a tweaked guardrail, or a piece of knowledge that is not indexed yet must save it first — polluting the production assistant — and the response only contains `{ reply, invoked_tool_names }`, so testers cannot tell which handler produced the answer, which tools ran with what arguments, whether a handoff happened, or how long the run took.

Upstream Chatwoot v4.18.0 shipped "improved playground testing" as an Enterprise-only feature (per-run scenario/rule/knowledge overrides, capped knowledge text injected as untrusted reference material, per-run agent naming, and a run-details trace). Because that implementation is EE-licensed, this change re-specifies the same product capability at the requirements level for Konversio's MIT `Pilot::` stack (see design.md for the clean-room approach).

## What Changes

- Accept an optional per-run **playground configuration** payload on the existing playground endpoint:
  - **Scenario selection**: choose which persisted scenarios participate in a run.
  - **Temporary scenarios**: unsaved scenario drafts (title, description, instruction, client-supplied identifier) that exist only for the duration of the run.
  - **Rule overrides**: per-run replacements for the assistant's response guidelines and guardrails.
  - **Knowledge text override**: a capped free-text snippet injected into the system prompt of every agent in the run as a clearly delimited, untrusted reference block (data to consult, never instructions to follow).
- Guarantee that a test run **never persists** anything: no scenario, rule, or knowledge override is written to the database.
- Assign temporary scenarios **per-run runtime agent names** so their handoff tools cannot collide with persisted scenario handoff tools, and so the trace can attribute replies and handoffs correctly.
- Collect a **run report** during the run via runner callbacks (tool start/complete, agent handoff) and return it in the playground response: the handler that produced the final reply, an ordered event log with sanitized tool arguments and truncated result previews, whether temporary knowledge was attached, and the run duration.
- Return structured `422` validation errors keyed by field path when the playground configuration is malformed.
- Extend the Playground UI with a test-setup panel (knowledge, scenarios, guidelines, guardrails) and a per-response run-report disclosure.

## Capabilities

### New Capabilities
- `pilot-playground-overrides`: Per-run, never-persisted overrides for scenario selection, temporary scenarios, response guidelines, guardrails, and capped knowledge text injected as untrusted reference material, with per-run agent naming and structured validation errors.
- `pilot-playground-run-report`: A per-run execution report returned with the playground response — final handler attribution, ordered tool and handoff events with sanitized arguments and truncated previews, knowledge-attached flag, and duration — plus its display in the Playground UI.

### Modified Capabilities

None.

## Impact

- `Api::V1::Accounts::Pilot::AssistantsController#playground` (accept optional config payload, structured 422 handling, extended response shape).
- `Custom::Pilot::AutopilotService` (accept an optional runtime configuration and run callbacks; inject the untrusted knowledge block into the system prompt; per-run agent naming for scenario agents).
- New services under `app/services/pilot/playground/` in the core tree (`Pilot::` namespace; no `enterprise/` paths).
- No database migrations — all overrides are transient per-run state; no new `pilot_` tables.
- Frontend: `app/javascript/dashboard/routes/dashboard/pilot/PlaygroundPanel.vue`, `app/javascript/dashboard/api/pilot/autopilot.js`, English `en.json` i18n only.
- Specs: new `spec/services/pilot/playground/` coverage and controller/request specs for the playground endpoint.
