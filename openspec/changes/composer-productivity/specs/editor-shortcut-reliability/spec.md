## Capability: editor-shortcut-reliability

Editor keyboard shortcuts behave correctly while focus is inside the composer: reply-mode shortcuts never fire while typing, send shortcuts respect open pickers, and Escape collapses the selection cleanly. (Modified capability — hardens behavior that exists in the fork base. Upstream reference: chatwoot/chatwoot#14526, shipped in v4.14.1, fixing issue #13446.)

---

## MODIFIED Requirements

### Requirement: reply-mode shortcuts are inert while typing

The `Alt+P` (private note) and `Alt+L` (reply) shortcuts — both the editor-focus bindings and the reply-mode toggle bindings — MUST NOT fire while focus is inside any typeable element (text input, textarea, contenteditable, including the reply editor itself). They SHALL continue to work when focus is outside typeable elements.

#### Scenario: typing alt characters does not switch modes

- Given the agent is typing in the reply editor
- When the agent presses a key combination that produces `Alt+P` or `Alt+L`
- Then the reply mode does not change
- And editor focus is not stolen

#### Scenario: shortcuts still work outside inputs

- Given focus is on a non-typeable element (e.g. the conversation list)
- When the agent presses `Alt+P` or `Alt+L`
- Then the corresponding reply-mode action fires as before

---

### Requirement: send shortcuts respect open pickers

The editor's send shortcuts (Enter and Cmd/Ctrl+Enter, per the agent's hotkey preference) MUST NOT send the message while any inline picker (mentions, canned responses, variables, macros, emoji, tools) is open.

#### Scenario: Enter selects instead of sending

- Given any inline picker is open in the reply editor
- When the agent presses Enter
- Then the highlighted picker item is selected
- And no message is sent

#### Scenario: send works when no picker is open

- Given no picker is open and the editor has content
- When the agent presses the configured send shortcut
- Then the message is sent

---

### Requirement: Escape collapses the editor selection

Pressing Escape inside the reply editor SHALL collapse the current text selection to a caret near the selection head, instead of expanding to a node selection (which keeps a visible highlight and can surface the floating formatting toolbar).

#### Scenario: Escape clears the highlight

- Given the agent has selected text in the reply editor
- When the agent presses Escape
- Then the selection collapses to a caret
- And no formatting toolbar appears
