## Context

Konversio's fork base (Chatwoot v4.13.0) already has macros (sidebar list, `macros/execute` store action, `POST /api/v1/accounts/:id/macros/:id/execute`), canned responses, agent/team mentions, message variables, and an emoji autocomplete in the reply editor. What it lacks is everything upstream shipped in v4.17.0 around the composer: keyboard-first macro execution and the rebuilt inline pickers. It also predates the v4.14.1 fix for `Alt+P`/`Alt+L` firing while typing.

All three items in this change are **MIT**. The upstream work lives entirely in the core tree (`app/javascript/...`) — no `enterprise/` involvement — so direct reference to upstream files and PRs is legal, and a near-verbatim port (adapted to Konversio's Pilot naming) is the intended approach. Upstream anchors:

- v4.17.0 macros + pickers: `app/javascript/dashboard/components-next/preview-picker/{PreviewPicker,CaretAnchoredPicker}.vue`, `composables/useMacroExecution.js`, `composables/useOrderedMacros.js`, `composables/commands/useMacroHotKeys.js`, `components/widgets/conversation/MacroList.vue`, and the rewritten `CannedResponse.vue` / `TagAgents.vue` / `VariableList.vue` / `keyboardEmojiSelector.vue`.
- v4.14.1 shortcut fix: upstream PR chatwoot/chatwoot#14526 (fixes #13446), touching `WootWriter/Editor.vue`, `WootWriter/ReplyTopPanel.vue`, and `useKeyboardEvents` spec coverage.

Naming adaptations for Konversio: the `@`-trigger tool menu gating uses Konversio's existing `enablePilotTools` prop / `usePilot` composable (upstream: `enableCaptainTools` / `useCaptain`); product copy says Konversio, not Chatwoot.

## Goals / Non-Goals

**Goals:**

- Run macros from the reply editor via a `#` picker with action preview and sidebar ordering.
- Run macros from the command bar on conversation and inbox routes.
- One shared macro execution path that gates resolve-type macros behind the conversation required-attributes modal.
- One shared caret-anchored picker primitive used by all four inline pickers (`/`, `@`, `{{`, `:`), with multi-word search, previews, and complete keyboard navigation.
- Canned response search across shortcode *and* content, client-side, with match highlighting and a resolved preview.
- Variable preview showing the resolved value for the current conversation; manual `{{variable}}` auto-resolution on closing braces.
- `Alt+P` / `Alt+L` never fire while typing in a typeable element.

**Non-Goals:**

- No backend changes; no new macro action types; no changes to the macros settings/builder UI beyond what already exists.
- No changes to the toolbar emoji button (`EmojiInput`) — upstream later swapped it for `EmojiIconPicker`; only the `:` keyboard picker is in scope here.
- No Giphy/GIF insertion (upstream shipped that separately, post-v4.18.0).
- No changes to Pilot tool insertion (`@` tools menu) beyond keeping its existing gating intact.
- No port of upstream's command-bar paywall prop (`isPaywalled`) — Konversio is self-hosted with no plan gating.

## Decisions

### Port upstream's shared picker primitive instead of patching `MentionBox`

Upstream replaced the old `MentionBox`-based popups with two primitives: `PreviewPicker.vue` (search input + listbox + preview pane with `side` / `stacked` / `none` layouts, ARIA combobox semantics) and `CaretAnchoredPicker.vue` (anchors a teleported card to the trigger caret coordinates, computes above/below placement and width from the editor and viewport, owns keyboard navigation via `useKeyboardNavigableList` + `useKeyboardEvents`, emits `select` / `close` / `removeTrigger`). Each content type is a thin component that maps records to `{ id, label, title, subtitle }` items plus a `preview` slot.

Alternatives considered:
- Keep `MentionBox` and bolt search/preview onto it. Rejected: four divergent popup implementations is exactly the inconsistency this change removes, and the clipping-inside-editor problem cannot be fixed without teleporting.
- Build one generic picker with per-type config objects instead of per-type wrapper components. Rejected: the per-type wrappers (`CannedResponse.vue`, `TagAgents.vue`, `VariableList.vue`, `MacroList.vue`, `keyboardEmojiSelector.vue`) keep data fetching, filtering, and preview rendering close to each content type, matching upstream and Konversio's existing component layout.

Rationale: porting the primitive keeps behavior identical to a battle-tested MIT implementation and minimizes original-design risk.

### Client-side fuzzy search for canned responses

Upstream fetches canned responses once (`getCannedResponse` with no `searchKey`) and filters client-side with `@chatwoot/pico-search` (weights: `shortCode` 1, `plainText` default), after resolving variables and stripping channel-unsupported formatting so the preview matches what insertion produces. Match highlighting and a leading-ellipsis snippet (24 chars of lead context) show why a deep match was returned.

Alternatives considered:
- Keep server-side `searchKey` filtering. Rejected: it stops at the first space, cannot search content and shortcode with different weights, and adds a request per keystroke.

Rationale: canned response lists are account-scoped and small; client-side search is what makes multi-word queries and previews possible. Adds one dependency (`@chatwoot/pico-search@0.6.2`).

### Shared macro execution composable with required-attribute gating

`useMacroExecution` is the single path for running a macro from the composer. It detects resolve-type macros (`resolve_conversation`, or `change_status` whose param resolves the conversation — the param may be the enum name or its integer value), checks the conversation's custom attributes against the account's required attributes (`useConversationRequiredAttributes`), and either runs immediately or returns the missing attributes so the caller opens `ConversationResolveAttributesModal`. Submitting the modal saves attributes, then runs; dismissing still runs (the backend declines to resolve while required attributes are empty) with a distinct "executed without resolving" alert. `executingMacroId` is exposed for spinner state.

Alternatives considered:
- Let the backend reject resolve-type macros and surface the error. Rejected: upstream's UX (collect attributes, then run) avoids a failed-run round trip and matches the existing resolve-flow modal.
- Duplicate the gating logic in the `#` picker and the command bar. Rejected: drift risk; the composable is consumed by both `ReplyBox.vue` (via `executeMacro` event) and `commands/useMacroHotKeys.js`.

### Sidebar ordering as the single macro order

`useOrderedMacros` sorts macros by the agent's saved `macros_display_order` UI setting; macros never arranged keep their store order at the end. Both the `#` picker and the command bar consume it, so all macro surfaces agree.

Alternatives considered: a separate order per surface. Rejected: no user benefit, extra settings surface.

### Command bar: dynamic macro actions, route-gated

`useMacroHotKeys` registers a `Run a macro` parent command with one child per macro (in sidebar order), only when the `macros` feature flag is on and the route is a conversation or inbox route. Macro records are fetched lazily when such a route becomes active. Selecting a child calls the shared execution path; pending required attributes open the same modal, which `commandbar.vue` hosts.

Alternatives considered: a static "open macros sidebar" command. Rejected: does not meet the "run without leaving the keyboard" goal.

### Editor keyboard handling: finish the mixin → composable migration

`ReplyBox.vue` drops `keyboardEventListenerMixins` (deleted upstream) and registers its shortcuts (`Escape`, `$mod+KeyK`, `Enter`, `$mod+Enter`) through `useKeyboardEvents`, with the open-picker guards (`showUserMentions`, `showCannedMenu`, `showVariablesMenu`, `showMacrosMenu`) checked before send. `Escape` in the editor collapses the selection instead of triggering ProseMirror's `selectParentNode`. The v4.14.1 fix sets `allowOnFocusedInput: false` on the `Alt+P` / `Alt+L` bindings in both `WootWriter/Editor.vue` (focus editor) and `WootWriter/ReplyTopPanel.vue` (switch reply/note mode), so they only fire when focus is outside typeable elements.

Alternatives considered: keep the mixin. Rejected: the mixin relies on a global handler registry indexed via DOM datasets; the composable uses an `AbortController` per component and is what all upstream v4.17.0 picker keyboard code builds on.

### Variable resolution on the client, Liquid-aware

`editorHelper.js` gains `resolveVariableText` / `resolveVariablesInMessage` (substitute `{{key}}` when a value exists and is not itself Liquid syntax, otherwise leave the placeholder for the backend), `getAgentVariables` / `getContactVariables` (name splitting/capitalization matching the backend drops, `{{agent.*}}` = message sender), and `createVariableInputRule` (a ProseMirror input rule that resolves a manually typed `{{key}}` when the closing braces arrive; disabled in private notes). The variable picker's preview shows the same resolved value.

Alternatives considered: resolve variables only at send time (backend). Rejected: the preview-then-insert UX is the point of the feature; the client mirrors backend drop semantics and leaves unresolved placeholders intact for the backend.

## Risks / Trade-offs

- **New dependency** (`@chatwoot/pico-search`) — MIT, upstream-pinned at 0.6.2; pin the same version.
- **Picker keyboard conflicts** — the picker takes focus while open; all send shortcuts must check the `show*Menu` flags before acting (ported `isAValidEvent` guard covers this).
- **Variable name divergence** — client-side name splitting must match the backend drops (`UserDrop`/`ContactDrop`); upstream's Ruby-capitalization mirror is ported as-is to avoid drift.
- **`{{` trigger vs literal braces** — the input rule only resolves when a value exists and the value is not Liquid; otherwise the typed text is untouched.

## Migration Plan

1. Add the picker primitives, composables, and per-type pickers; wire into `WootWriter/Editor.vue` and `ReplyBox.vue` behind the existing `macros` feature flag (other pickers are unconditional, replacing the old popups).
2. Register macro hotkeys in the command bar; delete `mentions/MentionBox.vue` and `keyboardEventListenerMixins` once no consumers remain.
3. Rollback: revert is frontend-only; no data or API changes.

## Open Questions

- None blocking. If Konversio's canned-response list payload proves too large for client-side search on some installs, server-side search can be reintroduced behind the same picker contract — measure first.
