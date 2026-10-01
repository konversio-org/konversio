## Capability: automation-condition-multi-value-input

Multi-value text conditions in automation rules (and the shared filter condition row) keep their values as arrays end-to-end instead of round-tripping through comma-joined strings, so values that themselves contain commas match literally. Fixes the upstream Chatwoot v4.17.1 bug "automation filters containing commas" (MIT).

---

## MODIFIED Requirements

### Requirement: multi-value text conditions preserve commas

Condition values for multi-value text inputs (such as the "message contains" content condition) MUST be stored, transmitted, and edited as arrays of distinct strings. The editor MUST NOT join values into a comma-separated string on load, and the payload builder MUST NOT split a single string on commas on save. Each value is committed individually (chip-style) in the UI.

#### Scenario: value containing a comma survives a save/edit round trip

- Given an automation rule with a content condition value `"hello, world"`
- When the rule is saved and later re-opened for editing
- Then the condition still has exactly one value, `"hello, world"`
- And the saved rule's conditions contain the single value `"hello, world"`, not `"hello"` and `" world"`

#### Scenario: multiple values are kept distinct

- Given a content condition with values `"refund"` and `"hello, world"`
- When the rule payload is generated for the API
- Then the condition's values array is exactly `["refund", "hello, world"]`

#### Scenario: no silent fragmentation of existing input

- Given the user commits a value containing commas in the multi-value input
- When the rule is saved
- Then the rule matches conversations against the full literal value, including the comma

---

### Requirement: chip-based multi-value input in the filter condition row

The shared filter condition row MUST render multi-value text conditions as an array-backed chip input: each committed value appears as a removable chip, and typing a new value commits it without interpreting commas as separators. Changing a condition's attribute or operator to a multi-value text type MUST reset the value to an empty array.

#### Scenario: committing a value adds a chip

- Given a multi-value text condition row
- When the user types `"hello, world"` and commits (Enter or blur)
- Then a single chip `"hello, world"` is added
- And the row's value is the array `["hello, world"]`

#### Scenario: removing a chip removes only that value

- Given a multi-value text condition with chips `"a"` and `"b"`
- When the user removes the `"a"` chip
- Then the row's value is `["b"]`

#### Scenario: switching to a multi-value text input resets values to an array

- Given a condition row whose value is a plain string or object
- When the attribute or operator changes to one using the multi-value text input
- Then the row's value resets to an empty array

---

### Requirement: legacy comma-split behavior is removed

The payload builder MUST NOT special-case any attribute (such as `content`) by splitting its values on commas, and the editable-rule mapper MUST NOT special-case multi-value conditions by joining values with commas.

needs investigation: rules saved under the old behavior may already hold fragmented values in the database (one intended value stored as two). Whether to ship a data repair re-joining known-fragmented conditions is undecided; the spec covers new behavior only.

#### Scenario: payload builder has no comma special case

- Given any automation condition whose values are an array of strings
- When the payload is generated
- Then the values are passed through unchanged regardless of the attribute key

#### Scenario: editing loads values as an array

- Given a saved automation rule whose multi-value condition values are `["x", "y,z"]`
- When the rule is mapped into the edit form
- Then the condition's values are the array `["x", "y,z"]`, not the string `"x,y,z"`
