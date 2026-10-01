## Why

Running a macro today means leaving the keyboard and the conversation: open the sidebar, find the macro, click run. The inline pickers in the reply editor (`/`, `@`, `{{`, `:`) are cramped, show no preview of what will be inserted, and their search stops at the first space — so agents cannot tell what a canned response contains before inserting it, and cannot search for "refund policy" across response bodies. On top of that, the `Alt+P` / `Alt+L` reply-mode shortcuts fire while the agent is typing in the editor, yanking focus and switching the editor mode mid-sentence (upstream issue chatwoot/chatwoot#13446, fixed in v4.14.1).

Upstream (Chatwoot v4.14.1 and v4.17.0, MIT-licensed core tree) solved all three: macros are runnable from the reply editor via `#` and from the command bar, the four inline pickers were rebuilt on a shared caret-anchored picker with multi-word search, previews, and full keyboard navigation, and the alt-shortcut misfire was fixed.

## What Changes

- Add a `#` trigger to the reply editor that opens a macro picker: type-ahead search over macro names, a preview pane listing each action the macro will run with resolved team/agent/label/priority names, and the same custom ordering the agent configured in the macros sidebar.
- Execute macros from the picker through a shared execution path that detects resolve-type macros (`resolve_conversation`, or `change_status` to resolved) and, when conversation required attributes are missing, opens the required-attributes modal before running; dismissing the modal still runs the macro (the backend leaves the conversation unresolved).
- Add a "Run a macro" group to the command bar (`Cmd/Ctrl+K`) listing macros in the same sidebar order, available on conversation and inbox routes, using the same execution path and required-attributes gating.
- Rebuild the inline pickers on a shared caret-anchored picker component: anchored to the trigger position, teleported to the body so it is not clipped by the editor, side preview when wide enough, stacked preview when tall enough, full keyboard navigation (arrows/Tab to move, Enter to select, Escape to close, Backspace on empty search removes the trigger).
- Canned response picker (`/`): fetch responses once and search client-side with fuzzy multi-word matching across shortcode and content; highlight matches; show a content snippet around deep matches; preview the response with variables resolved and channel-unsupported formatting stripped before insertion.
- Mention picker (`@`): agents and teams in one searchable list with All/Agents/Teams filter tabs, arrow-key tab navigation, and a preview showing agent availability/role or team auto-assign/membership.
- Variable picker (`{{`): standard message variables plus conversation/contact custom-attribute variables, searchable by key and description, with a preview of the value the variable resolves to in the current conversation. Also resolve a manually typed `{{variable}}` to its value when the closing braces are typed (public replies only).
- Emoji picker (`:`): opens after two characters, separator-insensitive search (space/underscore/hyphen) over emoji names and shortcodes.
- Fix the v4.14.1 shortcut regression: `Alt+P` / `Alt+L` no longer fire while focus is in a typeable element (upstream PR chatwoot/chatwoot#14526).

## Capabilities

### New Capabilities
- `macro-execution-from-composer`: Run macros from the reply editor (`#` picker) and the command bar, with action previews, sidebar ordering, and required-attribute gating for resolve-type macros.
- `inline-content-pickers`: Shared caret-anchored picker with multi-word search, match highlighting, and previews for canned responses, mentions, variables, and emojis in the reply editor.

### Modified Capabilities
- `editor-shortcut-reliability`: Editor keyboard shortcuts (`Alt+P`, `Alt+L`, Enter/Cmd+Enter send, Escape) behave correctly while focus is inside the editor — no mode switches or stray actions while typing.

## Impact

- `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue` — wire macro execution, `#` trigger state, required-attributes modal; keyboard handling moves from the deleted `keyboardEventListenerMixins` to `useKeyboardEvents`.
- `app/javascript/dashboard/components/widgets/WootWriter/Editor.vue` — new suggestion plugins (`#`, `:`), picker mounting, `enableMacros`/`enableInsertEvents` props, variable input rule, Alt-shortcut gating.
- `app/javascript/dashboard/components/widgets/WootWriter/ReplyTopPanel.vue` — `allowOnFocusedInput: false` for `Alt+P`/`Alt+L`.
- `app/javascript/dashboard/components-next/preview-picker/` (new: `PreviewPicker.vue`, `CaretAnchoredPicker.vue`) — shared picker primitives.
- `app/javascript/dashboard/components/widgets/conversation/` — `MacroList.vue` (new), `CannedResponse.vue`, `TagAgents.vue`, `VariableList.vue`, `WootWriter/keyboardEmojiSelector.vue` rebuilt on the shared picker; `mentions/MentionBox.vue` deleted.
- `app/javascript/dashboard/composables/` — new `useMacroExecution.js`, `useOrderedMacros.js`, `commands/useMacroHotKeys.js`; `useMacros.js` gains `resolveMacroActions`.
- `app/javascript/dashboard/routes/dashboard/commands/commandbar.vue` — register macro hotkeys and the required-attributes modal.
- `app/javascript/dashboard/helper/editorHelper.js` — variable resolution helpers, `collapseSelection`, empty-paragraph insertion fix.
- `app/javascript/dashboard/helper/commons.js` — `sanitizeVariableSearchKey`.
- Frontend i18n: `en.json` only (`CONVERSATION.PICKER.*`, `COMMAND_BAR.*`, `COMBOBOX.*`).
- New runtime dependency: `@chatwoot/pico-search` (client-side fuzzy search for canned responses).
- Backend: none — macro execution and canned response APIs already exist.
