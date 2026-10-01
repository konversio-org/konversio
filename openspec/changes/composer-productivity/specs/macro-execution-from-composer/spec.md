## Capability: macro-execution-from-composer

Run macros from the reply editor (`#` picker) and the command bar, with action previews, sidebar ordering, and required-attribute gating for resolve-type macros.

---

## ADDED Requirements

### Requirement: macro picker in the reply editor

When the account has the macros feature enabled, typing `#` in the reply editor SHALL open a macro picker anchored to the caret, listing the account's macros filtered by the text typed after the trigger. The picker MUST present macros in the same custom order the agent configured in the macros sidebar, with macros the agent never ordered appearing after the ordered ones.

#### Scenario: trigger opens the picker

- Given the agent is focused in the reply editor of a conversation
- And the account has the macros feature enabled
- When the agent types `#`
- Then a macro picker appears anchored to the caret position
- And it contains a search field pre-filled with any text already typed after the trigger

#### Scenario: search filters by macro name

- Given the macro picker is open
- When the agent types text into the search field
- Then only macros whose name contains the search text (case-insensitive) are listed
- And an empty-state label is shown when nothing matches

#### Scenario: macros follow sidebar ordering

- Given the agent has arranged macros in a custom order in the sidebar
- When the macro picker opens
- Then macros appear in that custom order
- And macros not present in the saved order appear at the end in their default order

#### Scenario: feature flag off — no trigger

- Given the account does not have the macros feature enabled
- When the agent types `#` in the reply editor
- Then no macro picker opens and the `#` is inserted as plain text

---

### Requirement: macro action preview

The macro picker SHALL show a preview of the selected macro's actions, resolving stored option ids to their display names (team, agent, label, priority) using the same option sources as the macro builder, and resolving attachment params to file names.

#### Scenario: preview shows resolved actions

- Given a macro with actions "assign team" (a stored team id), "add label" (a stored label id), and "change priority"
- When the agent highlights that macro in the picker
- Then the preview lists each action's name alongside the resolved team name, label title, and priority label — never raw ids

#### Scenario: preview shows action count in the list

- Given the macro picker is open
- Then each listed macro shows a subtitle with its action count

---

### Requirement: macro execution from the picker

Selecting a macro in the picker SHALL remove the `#` trigger text from the editor and execute the macro against the current conversation via the existing macro execute API, showing a success or error alert.

#### Scenario: selecting a macro runs it

- Given the macro picker is open on a conversation
- When the agent selects a macro
- Then the `#` trigger and any search text are removed from the editor
- And the macro is executed against the current conversation
- And a success alert is shown

#### Scenario: failed execution shows an error

- Given the macro execute request fails
- Then an error alert is shown
- And the conversation state is unchanged

---

### Requirement: required-attribute gating for resolve-type macros

A macro is resolve-type when it contains a `resolve_conversation` action, or a `change_status` action whose parameter resolves the conversation (the parameter MAY be the status enum name or its integer value). When a resolve-type macro is executed and the conversation is missing required custom attributes, the system SHALL open the required-attributes modal before running the macro; submitting the modal MUST save the attributes and then run the macro, and dismissing the modal MUST still run the macro with a distinct "executed without resolving" notice (the backend leaves the conversation unresolved while required attributes are empty). Non-resolve-type macros MUST run immediately without the modal.

#### Scenario: resolve-type macro with missing attributes prompts first

- Given a macro containing a `resolve_conversation` action
- And the account requires a conversation attribute that the current conversation has not filled
- When the agent runs the macro from the picker or the command bar
- Then the required-attributes modal opens listing the missing attributes
- And the macro has not yet executed

#### Scenario: submitting the modal runs the macro

- Given the required-attributes modal is open for a pending macro execution
- When the agent fills the attributes and submits
- Then the attributes are saved to the conversation
- And the macro is executed

#### Scenario: dismissing the modal still runs the macro

- Given the required-attributes modal is open for a pending macro execution
- When the agent dismisses the modal
- Then the macro is executed
- And the notice indicates the macro ran without resolving

#### Scenario: resolve-type macro with all attributes runs immediately

- Given a resolve-type macro and a conversation whose required attributes are all filled
- When the agent runs the macro
- Then the macro executes immediately without opening the modal

#### Scenario: change_status to resolved counts as resolve-type

- Given a macro whose only resolve-relevant action is `change_status` with the resolved status parameter
- When the agent runs it with missing required attributes
- Then the required-attributes modal opens before execution

#### Scenario: non-resolve macro never prompts

- Given a macro with only label/assignment actions
- When the agent runs it
- Then it executes immediately regardless of required attributes

---

### Requirement: run macros from the command bar

The command bar SHALL include a "Run a macro" command whose children are the account's macros in sidebar order, available when the macros feature is enabled and the current route is a conversation or inbox route. Running a macro from the command bar MUST use the same execution path and required-attribute gating as the reply-editor picker.

#### Scenario: macros appear as command bar children

- Given the agent is on a conversation route with the macros feature enabled
- When the agent opens the command bar and selects "Run a macro"
- Then the account's macros are listed in sidebar order

#### Scenario: command bar execution shares the gating

- Given a resolve-type macro run from the command bar with missing required attributes
- Then the required-attributes modal opens, and submit/dismiss behave as they do for the reply-editor picker

#### Scenario: hidden outside conversation routes

- Given the agent is on a settings route
- When the agent opens the command bar
- Then no "Run a macro" command is offered

---

### Requirement: keyboard and dismissal behavior of the macro picker

The macro picker SHALL be fully operable from the keyboard: move selection with arrows or Tab/Shift+Tab, select with Enter, close with Escape (returning focus to the editor), and remove the `#` trigger with Backspace when the search is empty. While the picker is open, the reply editor's send shortcuts MUST NOT fire.

#### Scenario: Escape closes and refocuses the editor

- Given the macro picker is open
- When the agent presses Escape
- Then the picker closes and focus returns to the editor

#### Scenario: Backspace on empty search removes the trigger

- Given the macro picker is open with an empty search field
- When the agent presses Backspace
- Then the picker closes and the `#` trigger text is deleted from the editor

#### Scenario: Enter does not send the message while picker is open

- Given the macro picker is open
- When the agent presses Enter
- Then the highlighted macro is selected
- And no message is sent
