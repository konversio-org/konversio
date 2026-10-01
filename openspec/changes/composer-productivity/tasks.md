## Tasks

All upstream references are MIT-licensed core-tree files; port and adapt to Konversio naming (`enablePilotTools`, Pilot copy).

### Backend

1. - [ ] **Confirm no backend work needed** — verify `macros/execute` store action and the macro execute API accept a single conversation id, and that the canned responses index endpoint returns the full account list without a `searchKey` param. File findings in the PR description; only add backend changes if verification fails.

### Frontend — shared primitives

2. - [ ] **PreviewPicker** — port `app/javascript/dashboard/components-next/preview-picker/PreviewPicker.vue`: search input (ARIA combobox), listbox with optional group headers, `side` / `stacked` / `none` preview layouts, `selectedIndex` + `search` models, scroll-selected-into-view without scrolling ancestors.
3. - [ ] **CaretAnchoredPicker** — port `app/javascript/dashboard/components-next/preview-picker/CaretAnchoredPicker.vue`: caret anchor element + `TeleportWithDirection` to body, above/below placement from viewport space, width capped by editor/viewport, preview-layout selection by available space, RTL-aware inline-start, keyboard nav (Tab/Shift+Tab move, Escape close, Backspace-on-empty-search emits `removeTrigger`), click-outside close.
4. - [ ] **Macro composables** — port `composables/useOrderedMacros.js` (`macros_display_order` UI setting, unordered macros last) and extend `composables/useMacros.js` with `resolveMacroActions` (resolve option ids to team/agent/label/priority names, attachment filenames via `macroHelper`).
5. - [ ] **useMacroExecution** — port `composables/useMacroExecution.js`: resolve-type detection (`resolve_conversation`, `change_status` to resolved incl. integer enum param), required-attribute check via `useConversationRequiredAttributes`, pending-execution flow (submit saves attributes then runs; dismiss runs with the "executed without resolving" alert), `executingMacroId` state.
6. - [ ] **Editor helpers** — port `editorHelper.js` additions: `resolveVariableText`, `resolveVariablesInMessage`, `getAgentVariables`, `getContactVariables`, `createVariableInputRule`, `collapseSelection`, empty-paragraph insertion fix in `insertAtCursor`; add `sanitizeVariableSearchKey` to `dashboard/helper/commons.js`.
7. - [ ] **Dependency** — add `@chatwoot/pico-search@0.6.2` to `package.json`.

### Frontend — pickers

8. - [ ] **CannedResponse picker** — rewrite `components/widgets/conversation/CannedResponse.vue` on `CaretAnchoredPicker`: fetch once on mount, pico-search over `shortCode` + resolved plain text, match highlighting with snippet lead-in, preview = variables resolved + `stripUnsupportedFormatting` + formatted message HTML; emits `replace` with raw content.
9. - [ ] **VariableList picker** — rewrite `components/widgets/conversation/VariableList.vue`: standard `MESSAGE_VARIABLES` + conversation/contact custom-attribute variables, search by key and description, preview shows description and resolved value (or "no value"), emits `selectVariable` with the key.
10. - [ ] **TagAgents (mentions) picker** — rewrite `components/widgets/conversation/TagAgents.vue`: agents + teams, All/Agents/Teams filter tabs with ArrowLeft/ArrowRight navigation (RTL-aware), preview with agent availability/role or team auto-assign/membership, emits `selectAgent`; delete `components/widgets/mentions/MentionBox.vue` when no consumers remain.
11. - [ ] **Emoji picker** — rewrite `components/widgets/WootWriter/keyboardEmojiSelector.vue` on `CaretAnchoredPicker`: separator-insensitive search over name + shortcode from `emojisGroup.json`, no results before a search term, emits `selectEmoji`.
12. - [ ] **MacroList picker** — add `components/widgets/conversation/MacroList.vue`: ordered macros filtered by name, subtitle with action count, timeline-style preview of `resolveMacroActions` output, emits `selectMacro`.

### Frontend — editor & command bar wiring

13. - [ ] **WootWriter Editor** — update `components/widgets/WootWriter/Editor.vue`: add `#` (macros, gated by new `enableMacros` prop) and `:` (emoji, min 2 chars) suggestion plugins via the shared `createSuggestionPlugin` factory; mount the five pickers with caret anchoring; add `enableInsertEvents` gating for `INSERT_INTO_RICH_EDITOR` bus events; add variable input rule; `Escape` collapses selection; set `allowOnFocusedInput: false` on `Alt+KeyP`/`Alt+KeyL`; emit `toggleMacrosMenu` / `executeMacro`; keep `enablePilotTools` gating of the `@` tools menu intact.
14. - [ ] **ReplyTopPanel** — set `allowOnFocusedInput: false` on the `Alt+P`/`Alt+L` reply-mode bindings in `components/widgets/WootWriter/ReplyTopPanel.vue` (upstream PR #14526).
15. - [ ] **ReplyBox** — update `components/widgets/conversation/ReplyBox.vue`: replace `keyboardEventListenerMixins` with `useKeyboardEvents` (Escape, `$mod+KeyK`, `Enter`, `$mod+Enter`), add `showMacrosMenu` state to the send-shortcut guard, pass `enable-macros` (feature-flag gated), `enable-insert-events`, `variables`, and editor `schema` to the editor, handle `execute-macro` via `useMacroExecution`, host `ConversationResolveAttributesModal`.
16. - [ ] **Command bar** — port `composables/commands/useMacroHotKeys.js` (feature-flag + conversation/inbox route gating, lazy macro fetch, parent `Run a macro` command with per-macro children in sidebar order, toy-brick icon) and register it in `routes/dashboard/commands/commandbar.vue` alongside `ConversationResolveAttributesModal`. Do not port upstream's `isPaywalled` prop.
17. - [ ] **Cleanup** — delete `shared/mixins/keyboardEventListenerMixins.js` once `ReplyBox.vue` is migrated and no other consumers remain (`grep -r keyboardEventListenerMixins app/javascript`).
18. - [ ] **i18n** — add `CONVERSATION.PICKER.*` (macro/mention/variable/emoji labels and placeholders), `COMMAND_BAR.SECTIONS.EXECUTE_MACRO`, `COMMAND_BAR.COMMANDS.EXECUTE_A_MACRO`, `COMBOBOX.*` keys to `app/javascript/dashboard/i18n/locale/en.json` only.

### Validation

19. - [ ] **JS specs** — port upstream specs: `composables/spec/useMacroExecution.spec.js`, `composables/spec/useOrderedMacros.spec.js`, `composables/spec/useMacros.spec.js` additions, `components/widgets/conversation/specs/ReplyBox.spec.js`, `routes/dashboard/commands/specs/commandbar.spec.js` macro cases, and the focused-input cases in `composables/spec/useKeyboardEvents.spec.js` (Alt+P/Alt+L ignored while typing). Run `pnpm test`.
20. - [ ] **Lint** — `pnpm eslint` clean on all touched files.
21. - [ ] **Manual smoke** — in a conversation: type `#` → search → preview → run a resolve-type macro with missing required attributes (modal appears; submit runs; dismiss runs without resolving); run a macro from `Cmd/Ctrl+K`; `/` multi-word canned search with highlight + preview; `@` mention with filter tabs; `{{` variable with value preview and manual-brace resolution; `:sm` emoji search; type `alt+p`/`alt+l` mid-sentence and confirm nothing happens.

## Dependencies / Order

Tasks 2–3 (primitives) block 8–12 (pickers). Tasks 4–6 block 12, 13, 15, 16. Task 7 blocks 8. Tasks 8–12 can run in parallel once 2–3 land. Task 13 depends on 8–12; tasks 15–16 depend on 13 and 5. Task 17 runs last among frontend changes (after 15). Task 18 parallel to 8–16. Tasks 19–21 validate the whole chain.
