## Capability: pilot-scenario-tool-controls

Enable/disable toggles for scenarios and custom tools: non-destructive, protective against disabling referenced tools, and excluding disabled items from run time.

---

## ADDED Requirements

### Requirement: Scenario listing includes disabled scenarios

The scenario index API SHALL return all of an assistant's scenarios, enabled and disabled, exposing each scenario's `enabled` flag. Only enabled scenarios SHALL be registered with the agent framework at run time.

#### Scenario: index returns enabled and disabled scenarios

- Given an assistant with one enabled and one disabled scenario
- When the scenario index is fetched
- Then both scenarios are returned with their `enabled` flags

#### Scenario: disabled scenario is inactive at run time

- Given an assistant with a disabled scenario
- When the assistant runs on a conversation
- Then the disabled scenario is not available as a handoff target

---

### Requirement: Scenario enable/disable toggle

Users SHALL be able to toggle a scenario's `enabled` flag from the assistant's scenario list without editing its content. The toggle MUST show a pending state while saving and MUST surface success and failure feedback.

#### Scenario: disabling keeps the scenario's content

- Given an enabled scenario with an instruction referencing tools
- When the user disables it
- Then the scenario's title, description, instruction, and tool references are unchanged
- And it no longer participates in runs

#### Scenario: re-enabling restores behavior

- Given a disabled scenario
- When the user re-enables it
- Then it participates in runs again exactly as before

---

### Requirement: Custom tool enable/disable with referenced-scenario protection

Each custom tool SHALL expose the count of enabled scenarios that reference it. Disabling a tool referenced by one or more enabled scenarios SHALL require the user to confirm a dialog stating that count. A disabled tool MUST be excluded from every assistant's live toolset and MUST NOT satisfy scenario tool-reference validation for new references; existing references in stored scenarios MUST be preserved (the scenario simply has no live tool while the tool is disabled).

#### Scenario: referenced tool shows its usage count

- Given two enabled scenarios referencing the custom tool "order_lookup"
- When the Tools page is fetched
- Then "order_lookup" reports a referencing-scenario count of 2

#### Scenario: disabling a referenced tool requires confirmation

- Given a custom tool referenced by an enabled scenario
- When the user switches the tool off
- Then a confirmation dialog appears stating how many enabled scenarios reference it
- And the tool is disabled only after the user confirms

#### Scenario: disabling an unreferenced tool needs no confirmation

- Given a custom tool referenced by no enabled scenario
- When the user switches it off
- Then the tool is disabled immediately without a confirmation dialog

#### Scenario: disabled tool is excluded from assistant toolsets

- Given a disabled custom tool previously available to an assistant
- When the assistant's available tools are enumerated for a run
- Then the disabled tool is not included

#### Scenario: re-enabling restores stored references

- Given a scenario whose stored tool references include a disabled tool
- When the tool is re-enabled
- Then the scenario's referenced tool is live again without any edit to the scenario
