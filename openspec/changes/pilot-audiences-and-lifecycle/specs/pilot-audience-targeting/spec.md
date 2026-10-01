## Capability: pilot-audience-targeting

Per-assistant audience condition trees that decide whether a Pilot assistant engages a conversation, with server-side validation and evaluation semantics aligned with core contact filtering.

---

## ADDED Requirements

### Requirement: Audience condition tree stored per assistant

Each `Pilot::Assistant` SHALL store an optional audience definition in its `config` as a recursive condition tree. A node is either a **group** (a combinator and a non-empty list of child nodes) or a **leaf** (an attribute key, a filter operator, and a list of comparison values). Groups combine children with logical AND or OR. Nesting SHALL be limited to a root group, at most one level of sub-groups, and leaves (maximum depth 3). A blank or absent audience SHALL mean the assistant engages all contacts.

#### Scenario: no audience configured engages everyone

- Given an assistant with no `audience` key in its config
- When any conversation is evaluated for engagement
- Then the audience check passes

#### Scenario: tree persists through the assistant API

- Given an assistant exists
- When the assistant is updated with a valid audience tree via the assistant update API
- Then subsequent reads of the assistant return the same tree

#### Scenario: audience updates merge with existing config

- Given an assistant with `handoff_message` already set in config
- When the assistant is updated with only an `audience` key
- Then the `handoff_message` value is preserved

---

### Requirement: Server-side audience validation

The system SHALL validate the audience tree on assistant create/update and MUST reject invalid trees with an error on the assistant's config. Validation MUST enforce: node shape (group vs leaf), group combinators limited to AND/OR, non-empty condition lists, maximum depth 3, operator compatibility with the target attribute (per standard attribute and per custom-attribute display type as defined by the account's custom attribute definitions), presence of comparison values for operators that require them, and absence of values for operators that take none.

#### Scenario: leaf with incompatible operator is rejected

- Given an audience leaf targeting a date attribute with a text-containment operator
- When the assistant is saved
- Then validation fails with a config error and the assistant is not persisted

#### Scenario: tree deeper than three levels is rejected

- Given an audience tree with a group nested inside a sub-group
- When the assistant is saved
- Then validation fails with a config error

#### Scenario: empty condition list is rejected

- Given a group node with an empty conditions array
- When the assistant is saved
- Then validation fails with a config error

#### Scenario: presence-style operators require no values

- Given a leaf using an is-present style operator with no values
- When the assistant is saved
- Then validation passes

---

### Requirement: Audience evaluation semantics

Audience evaluation SHALL be performed in memory against the conversation's contact and the conversation. Attribute resolution MUST cover: contact standard attributes (e.g. name, email, phone number, identifier, blocked state, created/last-activity timestamps), contact additional attributes (e.g. country, city, company), contact labels, conversation additional attributes (e.g. browser language), widget identity-verification (HMAC) state, and contact custom attributes (typed per the account's custom attribute definitions). Comparison semantics MUST match core contact filtering: case-insensitive text comparison, phone numbers compared ignoring the `+` prefix, label conditions as has-tag checks, unset checkbox custom attributes treated as false, numeric comparison for numeric custom attribute types, ISO date strings in custom attributes treated as dates, and blank or unparseable actual values never matching range or date operators.

#### Scenario: AND group requires all children to match

- Given an audience root group with combinator AND and two leaf conditions
- And the contact satisfies only one of them
- When the audience is evaluated
- Then the audience does not match

#### Scenario: OR group requires any child to match

- Given an audience root group with combinator OR and two leaf conditions
- And the contact satisfies exactly one of them
- When the audience is evaluated
- Then the audience matches

#### Scenario: label leaf behaves as has-tag check

- Given an audience leaf requiring the contact label "vip"
- And the contact's label list includes "vip"
- When the audience is evaluated
- Then the leaf matches

#### Scenario: unparseable range comparison never matches

- Given an audience leaf requiring a custom number attribute to be greater than 100
- And the contact's value for that attribute is blank
- When the audience is evaluated
- Then the leaf does not match

#### Scenario: identity-verification leaf reads widget HMAC state

- Given an audience leaf requiring the contact to be identity-verified
- And the conversation's contact inbox is HMAC verified
- When the audience is evaluated
- Then the leaf matches

---

### Requirement: Audience gates Pilot engagement at conversation creation

When a conversation's initial status is determined on an inbox with an attached Pilot assistant, the audience check SHALL decide whether the assistant engages. A conversation whose contact/conversation does not match the audience MUST start `open` (human queue) rather than `pending`, and the assistant MUST NOT reply on it. Audience changes MUST NOT re-gate conversations already in progress.

#### Scenario: non-matching contact starts open

- Given an assistant whose audience requires the label "vip"
- And a new conversation arrives from a contact without that label
- When the conversation is created
- Then its status is `open`

#### Scenario: matching contact starts pending

- Given an assistant whose audience requires the label "vip"
- And a new conversation arrives from a contact labeled "vip"
- When the conversation is created
- Then its status is `pending` and the assistant may respond

#### Scenario: audience edit does not affect in-flight conversations

- Given a `pending` conversation the assistant is handling
- When the assistant's audience is edited so the contact no longer matches
- Then the conversation remains `pending` and the assistant continues handling it

---

### Requirement: Audience builder UI

The Pilot assistant settings MUST provide an audience editor offering an everyone / specific-audience choice. In specific mode the editor MUST allow building the condition tree (root AND/OR group, one nested sub-group level, leaf rows with attribute, operator, and value inputs reusing the advanced-filter attribute and operator primitives), MUST prevent saving an empty condition set, and MUST persist through the assistant update API.

#### Scenario: everyone mode clears the tree

- Given an assistant with a saved audience tree
- When the user switches to the everyone option and saves
- Then the assistant's audience config is cleared

#### Scenario: empty specific audience is blocked

- Given the user selects the specific-audience option without adding any condition
- When the user attempts to save
- Then an inline validation message is shown and no API call is made

#### Scenario: saved tree round-trips into the editor

- Given an assistant with a saved two-condition AND audience
- When the user opens the audience editor
- Then both conditions are rendered with their attribute, operator, and values
