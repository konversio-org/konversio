# Handoff: Claude → Gemini — Lifecycle tabs (tasks 2.6 / 2.7)

**Context.** Claude built and pushed the base feature on branch `feat/ai-agents-observability`
(commit `6d1f050`, rebased onto current `origin/main`). Gemini owns the new lifecycle-tabs
work (spec §2.6, §2.7, verification §5.6–5.9). This file is the build brief. Branch off
`feat/ai-agents-observability` (do NOT start from main — you need the AI Agent view to exist).

## What already exists (don't rebuild)

- Route `ai_agent_dashboard` (`/ai-agent/:agentId`) + `ai_agent_inbox_dashboard`
  (`/ai-agent/:agentId/inbox/:inboxId`) → `ConversationView` with prop `pilotAssistantId`.
- `ChatList.vue` already receives `pilotAssistantId`, puts it in `conversationFilters`,
  and the backend `ConversationFinder#filter_by_pilot_assistant` scopes by it.
- **So: when `props.pilotAssistantId` is truthy, you are in the AI Agent view.** That is your
  switch for showing lifecycle tabs instead of assignee tabs.

## The tab system today (read these first)

- `app/javascript/dashboard/components/ChatList.vue`
  - `activeAssigneeTab` ref (`me` | `unassigned` | `all`, from `wootConstants.ASSIGNEE_TYPE`).
  - `assigneeTabItems` computed → built from `ASSIGNEE_TYPE_TAB_PERMISSIONS`, each item
    `{ key, name: t('CHAT_LIST.ASSIGNEE_TYPE_TABS.<key>'), count: conversationStats[countKey] }`.
  - Template: `<ChatTypeTabs v-if="!hasAppliedFiltersOrActiveFolders" :items="assigneeTabItems"
    :active-tab="activeAssigneeTab" @chat-tab-change="updateAssigneeTab" />`.
  - `conversationFilters` computed includes `assigneeType: activeAssigneeTab.value` and
    `status: activeStatus.value`.
  - `conversationList` computed branches on `activeAssigneeTab.value` to pick the store getter
    (`mineChatsList` / `unAssignedChatsList` / `allChatList`).
- `app/javascript/dashboard/components/widgets/ChatTypeTabs.vue` — the tab strip. Generic
  (`items`, `active-tab`, emits `chat-tab-change`). **Do not fork it; just feed it different items.**
- Counts source: `conversationStats` getter (`conversationStats/get`), backed by
  `ConversationFinder#perform_meta_only` → `{ mine_count, assigned_count, unassigned_count, all_count }`.
- Backend `app/finders/conversation_finder.rb`:
  - `filter_by_assignee_type` already supports `me` / `unassigned` / `assigned`.
  - `filter_by_status` already supports `open` / `resolved` / `all` via `params[:status]`.
  - `filter_by_pilot_assistant` (Claude added) scopes to the AI agent.

## Recommended approach — NO new backend filter, NO migration

The three lifecycle tabs map onto **combinations of `status` + `assignee_type` that the finder
already supports**. Keep mutually-exclusive buckets:

| Tab          | status   | assignee_type | meaning                                  |
|--------------|----------|---------------|------------------------------------------|
| **Active**   | open     | unassigned    | AI handling, no human yet                |
| **Handed Off command**| open     | assigned      | escalated to a human, still open         |
| **Resolved** | resolved | (any)         | closed/done                              |

This satisfies spec §2.7 ("open/unassigned, assigned, resolved") and the design's
"no new persistence" rule. **Confirm this matrix with Rob** — the one ambiguity is whether a
*resolved + previously-assigned* convo belongs in Resolved (recommended: yes, Resolved wins).
Snoozed/pending: fold into Active unless Rob says otherwise.

## Frontend work (scoped to AI Agent view only)

1. In `ChatList.vue`, add `const isAiAgentView = computed(() => !!props.pilotAssistantId)`.
2. Add a lifecycle tab model, e.g. `activeLifecycleTab` ref defaulting to `active`, and
   `lifecycleTabItems` computed → `[{key:'active',...},{key:'handed_off',...},{key:'resolved',...}]`
   with `name: t('CHAT_LIST.AI_AGENT_LIFECYCLE_TABS.<key>')` and a count each (see counts below).
3. In the template, swap the tab source by view:
   `:items="isAiAgentView ? lifecycleTabItems : assigneeTabItems"`,
   `:active-tab="isAiAgentView ? activeLifecycleTab : activeAssigneeTab"`, and route
   `@chat-tab-change` to a handler that sets the right ref. **Other views must be untouched
   (§5.9).**
4. Make `conversationFilters` reflect the active lifecycle tab when `isAiAgentView`:
   map `active → {status:'open', assigneeType:'unassigned'}`,
   `handed_off → {status:'open', assigneeType:'assigned'}`,
   `resolved → {status:'resolved', assigneeType:undefined}`.
   Reuse the existing `status` + `assigneeType` keys already flowing to `ConversationApi.get`
   (they already snake-case to `status` / `assignee_type`). No API change needed.
5. `conversationList` / store getters: the filtered results already come back scoped; reuse the
   existing `allChatList(filters)` path for the AI view (don't reuse the me/unassigned getters,
   since the lifecycle buckets are status+assignee combos, not pure assignee). Verify the store
   getter keys conversations by the same filter signature.

## Counts (the only fiddly part)

`conversationStats` today returns mine/assigned/unassigned/all — not status-split, and not
scoped to `pilot_assistant_id`. Options, simplest first:
- **A (recommended):** call the conversations `meta` endpoint (which runs
  `ConversationFinder#perform_meta_only`) once per lifecycle tab with that tab's
  `status`+`assignee_type`+`pilot_assistant_id`, read the relevant count. Three light calls,
  no backend change. Wire via `conversationStats/get` or a small dedicated fetch.
- **B:** extend `perform_meta_only` to also return `resolved_count` and accept the
  `pilot_assistant_id` scope, then derive: Active=unassigned_count(open),
  Handed Off=assigned_count(open), Resolved=resolved_count. More backend work; do only if A is too chatty.

Start with A. If counts feel wrong, check that the meta call carries `pilot_assistant_id`
(the meta endpoint params live in `api/inbox/conversation.js#meta` — it does NOT currently send
`pilot_assistant_id`, so you'll need to add it there too, mirroring how `get` was extended).

## i18n (English only — `app/javascript/dashboard/i18n/locale/en/`)

Add under the appropriate `CHAT_LIST` block (Claude put `SIDEBAR.AI_AGENTS` in `settings.json`;
tab strings likely belong in `chatlist.json` — check where `ASSIGNEE_TYPE_TABS` lives and colocate):
```
AI_AGENT_LIFECYCLE_TABS: { ACTIVE: "Active", HANDED_OFF: "Handed Off", RESOLVED: "Resolved" }
```
Keep participation/lifecycle language; don't reintroduce "Mine/Handled".

## Verification (spec §5.6–5.9) — local OrbStack, Acme seed, Mira = `Pilot::Assistant` id=1

- §5.6 AI Agent view shows Active / Handed Off / Resolved.
- §5.7 each tab filters correctly (assign a Mira convo to John → moves to Handed Off; resolve it
  → moves to Resolved; reopen+unassign → Active).
- §5.8 Mine/Unassigned/All are NOT shown in the AI Agent view.
- §5.9 Channels / All Conversations / Teams views still show the original assignee tabs.
- Lint before commit: `pnpm eslint <changed .vue/.js>`; `bundle exec rubocop -a` on any Ruby.
  (Container bundler is currently broken — run rubocop on the host via rbenv, as Claude did.)
- Acme widget token (chatwoot_dev DB): `n8FoFCQ5YP1nezTJWz498Y5H`; login john@acme.inc / Password1!.

## Coordination

- Claude will NOT touch the tab files — they're yours. Claude's branch is pushed; rebase your
  work on top of `origin/feat/ai-agents-observability` (or commit onto the same branch — agree
  with Rob which). Re-fetch before pushing; check for the other agent's commits first.
- Do not touch the shared `SidebarSubGroup.vue` / `SidebarGroup.vue` collapse behavior — Rob
  decided to keep the upstream "active item dangles on collapse" behavior on purpose.
