## Capability: pilot-agent-turn-budget

A bounded turn budget for the autopilot agent loop: one budget per customer turn, a conservative default, safe configuration handling, and defined failure behavior when the budget is exhausted.

---

## ADDED Requirements

### Requirement: bounded turns per customer turn

Each autopilot run SHALL execute the agent loop with a finite turn budget covering the model turns and tool calls of that run. The default budget SHALL be conservative and MUST NOT exceed 10 turns.

#### Scenario: run executes within the budget

- Given a customer message that requires two tool calls
- When the autopilot run executes
- Then the agent loop completes within the turn budget and produces a reply

#### Scenario: default budget is conservative

- Given no explicit configuration
- When the turn budget is resolved
- Then the default is a positive integer not exceeding 10

---

### Requirement: safe configuration

The turn budget SHALL be configurable per installation via the existing `PILOT_AUTOPILOT_MAX_TURNS` configuration surface. Non-positive, non-numeric, or otherwise invalid values SHALL fall back to the default.

#### Scenario: valid configuration is honored

- Given `PILOT_AUTOPILOT_MAX_TURNS` set to a positive integer
- When the turn budget is resolved
- Then that value is used

#### Scenario: invalid configuration falls back

- Given `PILOT_AUTOPILOT_MAX_TURNS` set to 0, a negative number, or a non-numeric string
- When the turn budget is resolved
- Then the default budget is used

---

### Requirement: exhaustion is a run failure

Turn-budget exhaustion SHALL be treated as a run failure: no partial reply SHALL be delivered, and the failure SHALL route through the existing error path that hands the conversation off to a human.

#### Scenario: exhausted budget hands off instead of delivering partial output

- Given a run that exhausts its turn budget while still invoking tools
- When the run ends
- Then no AI reply is delivered to the customer
- And the conversation is handed off via the error path

- needs investigation: how the ai-agents runner signals turn-budget exhaustion in Konversio's pipeline (generic `failed?` vs a distinct error), so the exhaustion → error-handoff wiring is explicit.
