## Capability: inline-content-pickers

Shared caret-anchored picker with multi-word search, match highlighting, and previews for canned responses (`/`), mentions (`@`), variables (`{{`), and emojis (`:`) in the reply editor.

---

## ADDED Requirements

### Requirement: shared caret-anchored picker behavior

All inline pickers in the reply editor SHALL be anchored to the trigger caret position, rendered outside the editor's clipping context (teleported), sized to the editor width up to a maximum, and placed above or below the caret based on available viewport space. When space allows, the picker MUST show a preview pane beside the list; in constrained space the preview MUST stack below the list; when neither fits, the preview is omitted. Every picker MUST support full keyboard navigation: move with arrows or Tab/Shift+Tab, select with Enter or click, close with Escape (focus returns to the editor), and remove the trigger character with Backspace when the search field is empty. The picker's search field SHALL be pre-filled with text already typed after the trigger, including text from a restored draft.

#### Scenario: picker is anchored and not clipped

- Given the agent is typing near the bottom of a tall editor
- When a picker opens
- Then it is positioned at the caret line and fully visible within the viewport

#### Scenario: search continues from typed text

- Given the agent has typed `@eng` in the editor
- When the mention picker opens
- Then its search field contains "eng" and the list is already filtered

#### Scenario: layout adapts to available space

- Given a wide editor with ample viewport height
- When a picker with a preview opens
- Then the preview appears beside the list
- And in a narrow or short context the preview stacks below the list or is hidden

#### Scenario: trigger removal with Backspace

- Given any picker is open with an empty search field
- When the agent presses Backspace
- Then the picker closes and the trigger characters are removed from the editor

---

### Requirement: canned response picker with search and preview

Typing `/` in a public reply SHALL open a canned response picker that searches client-side across both shortcode and response content, supporting multi-word queries. Matching text MUST be highlighted in the results, and when a match occurs deep inside a response body the list entry MUST show a snippet around the match with a leading ellipsis. The picker MUST show a preview of the selected response exactly as it would be inserted: variables resolved against the current conversation and formatting the channel cannot carry stripped. Selecting a response MUST insert its content at the trigger position with variables resolved.

#### Scenario: multi-word search matches content

- Given a canned response whose body contains "refund policy"
- When the agent types `/refund policy`
- Then that response remains in the results with the match highlighted

#### Scenario: snippet shown for deep matches

- Given a long canned response whose match is far from the start of the body
- When it appears in the results
- Then its subtitle shows a snippet beginning with an ellipsis and containing the highlighted match

#### Scenario: preview reflects insertion

- Given a canned response containing `{{contact.name}}` and rich formatting on a channel that does not support that formatting
- When the agent highlights the response
- Then the preview shows the content with the contact's name filled in and the unsupported formatting stripped

#### Scenario: selecting inserts the response

- Given the canned response picker is open
- When the agent selects a response
- Then the `/` trigger and search text are replaced by the response content with variables resolved

#### Scenario: private notes do not trigger canned responses

- Given the editor is in private note mode
- When the agent types `/`
- Then no canned response picker opens

---

### Requirement: mention picker with agents, teams, and previews

Typing `@` in a context where mentions are allowed SHALL open a mention picker listing verified agents and teams, filterable by name, with an All/Agents/Teams filter tab row. The picker MUST show a preview for the selected entry: for agents, their availability status and role; for teams, whether auto-assignment is enabled and whether the current user is a member.

#### Scenario: agents and teams in one list

- Given the agent types `@` in a private note
- When the mention picker opens
- Then agents and teams are listed, grouped or filterable by type
- And each agent entry shows name and email; each team entry shows name and description

#### Scenario: filter tabs narrow the list

- Given the mention picker is open
- When the agent activates the Teams tab
- Then only teams are listed
- And the tab can be changed with the left/right arrow keys when the search field is empty

#### Scenario: preview shows agent details

- Given an agent entry is highlighted
- Then the preview shows that agent's availability status and role

#### Scenario: selecting inserts the mention

- Given the mention picker is open
- When the agent selects an agent or team
- Then the trigger text is replaced by the mention for that agent or team

---

### Requirement: variable picker with resolved-value preview

Typing `{{` in a public reply SHALL open a variable picker listing the standard message variables plus the account's conversation-level and contact-level custom attributes, searchable by variable key and description. The picker MUST show a preview containing the variable's description and the value it resolves to in the current conversation, or a "no value" indication when unresolved. Selecting a variable MUST insert its resolved value when one exists, and the `{{key}}` placeholder otherwise (leaving it for backend resolution at send time).

#### Scenario: custom attributes are listed with prefixed keys

- Given the account has a conversation custom attribute and a contact custom attribute
- When the variable picker opens
- Then both appear with their prefixed custom-attribute keys and descriptions

#### Scenario: preview shows the resolved value

- Given the current conversation's contact is named "Jane Doe"
- When the agent highlights the contact name variable
- Then the preview shows the resolved value for the current conversation

#### Scenario: unresolved variable inserts the placeholder

- Given a variable with no value in the current conversation
- When the agent selects it
- Then the `{{key}}` placeholder is inserted unchanged

#### Scenario: manual brace completion resolves inline

- Given the agent manually types `{{contact.first_name}}` in a public reply and a value exists
- When the closing braces are typed
- Then the typed placeholder is replaced by the resolved value

#### Scenario: manual brace completion leaves unknown or Liquid values alone

- Given the agent manually types a variable with no value, or whose value itself contains template syntax
- When the closing braces are typed
- Then the typed text is left unchanged for backend resolution

#### Scenario: private notes never resolve variables

- Given the editor is in private note mode
- When the agent types `{{` or completes a manual variable
- Then no picker opens and no inline resolution occurs

---

### Requirement: emoji picker via colon trigger

Typing `:` followed by at least two characters in the reply editor SHALL open an emoji picker whose search is insensitive to spaces, underscores, and hyphens, matching against both emoji names and shortcodes. Selecting an emoji MUST insert it at the trigger position.

#### Scenario: separator-insensitive search

- Given the agent types `:grinning face`, `:grinningface`, or `:grinning_face`
- Then the same emoji is found in each case

#### Scenario: no picker before two characters

- Given the agent types `:s`
- Then no emoji picker opens

#### Scenario: selecting inserts the emoji

- Given the emoji picker is open
- When the agent selects an emoji
- Then the trigger text is replaced by the emoji character
