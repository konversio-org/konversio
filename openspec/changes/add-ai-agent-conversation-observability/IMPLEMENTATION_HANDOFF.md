# AI Agents Observability — Implementation Handoff

Branch: `feat/ai-agents-observability` (off main). Nothing pushed. Working tree had only `openspec/` untracked at start.

## DONE (verified via `git diff`)

### Task 1 — ConversationFinder filter (`app/finders/conversation_finder.rb`)
- Added `filter_by_pilot_assistant` to `set_up` (after `filter_by_source_id`).
- New private method uses an EXISTS subquery on `messages` (sender_type='Pilot::Assistant' AND sender_id = :assistant_id). One row per conversation, no `.distinct`. Returns early if `params[:pilot_assistant_id]` blank. inbox_id drill-down already handled by existing `set_inboxes`/`find_conversation_by_inbox`.

### Task 2 — Conversation model + jbuilder payload
- `app/models/conversation.rb`: added `participating_pilot_assistants` (after `human_replied_since?`, before `unread_messages`):
  ```ruby
  def participating_pilot_assistants
    account.pilot_assistants.where(
      id: messages.where(sender_type: 'Pilot::Assistant').select(:sender_id)
    )
  end
  ```
- `app/views/api/v1/conversations/partials/_conversation.json.jbuilder`: inside `json.meta do`, after `hmac_verified`, added `json.pilot_assistants` array of `{id, name}`. Frontend reads `chat.meta.pilot_assistants`.
- Confirmed: `account.pilot_assistants` assoc exists; `Pilot::Assistant has_many :messages, as: :sender`; `Pilot::Assistant has_many :pilot_inboxes` + `has_many :inboxes, through: :pilot_inboxes`.

## DONE (frontend) — implemented on branch `feat/ai-agents-observability`

### Task 3 — routes + ConversationView + ChatList + API  [DONE]
- `conversation.routes.js`: added `ai_agent_dashboard` (`accounts/:accountId/ai-agent/:agentId`, props `{ pilotAssistantId: route.params.agentId }`) and `ai_agent_inbox_dashboard` (`.../ai-agent/:agentId/inbox/:inboxId`, props `{ pilotAssistantId, inboxId }`), inserted before `label_conversations`. Both use `CONVERSATION_PERMISSIONS`.
- `ConversationView.vue`: added prop `pilotAssistantId: { type:[String,Number], default:0 }`; passes `:pilot-assistant-id="pilotAssistantId"` to `<ChatList>`.
- `ChatList.vue`: added prop `pilotAssistantId`; added `pilotAssistantId: props.pilotAssistantId || undefined` to `conversationFilters`; added `watch(computed(() => props.pilotAssistantId), () => resetAndFetchData())`.
- `api/inbox/conversation.js`: `get()` now destructures `pilotAssistantId` and sends `pilot_assistant_id: pilotAssistantId`. (camelCase `pilotAssistantId` flows from conversationFilters -> store -> ConversationApi.get unchanged.)

### Task 4 — Sidebar AI Agents group  [DONE]
- `Sidebar.vue`: added `const pilotAssistants = useMapGetter('pilot/assistants/getRecords')`; dispatch `store.dispatch('pilot/assistants/fetch')` in `onMounted`.
- Store facts confirmed from `store/pilot/assistants/index.js`: `namespaced: true`, getter `getRecords` = `state.records`, fetch action = `fetch` (mutation type strings literally namespaced `'pilot/assistants/...'`). So getter key `pilot/assistants/getRecords` and action `pilot/assistants/fetch` are correct.
- **Assistant->inbox metadata: FIXED.** The existing `app/views/api/v1/accounts/pilot/assistants/_assistant.json.jbuilder` only exposed `enabled_inbox_count` (a count, no ids/names), so the sidebar group would never have rendered. Added `json.inboxes assistant.inboxes do |inbox| json.id/name/channel_type end` to the partial (uses the confirmed `has_many :inboxes, through: :pilot_inboxes` assoc). This is the ONLY backend file I touched, and it is required for task 1.1. The frontend `connectedInboxesForAssistant(assistant)` consumes `assistant.inboxes` (array of `{id,name,channel_type}`), mapping each to the account inbox record (`inboxes/getInboxes`) so `ChannelIcon`/`ChannelLeaf` get the full inbox object; it also falls back to `assistant.pilot_inboxes` join rows if ever present.
- `customerFacingAssistants` computed = assistants with >=1 connected inbox. Group inserted between Channels and Labels via `...(customerFacingAssistants.value.length ? [aiAgentsGroup.value] : [])`. Each assistant child -> `ai_agent_dashboard`; per connected-inbox grandchild -> `ai_agent_inbox_dashboard` using `ChannelIcon` + `ChannelLeaf` (same pattern as Channels).
- Group label uses i18n key `SIDEBAR.AI_AGENTS` (SidebarGroup renders the `label` prop, consistent with Channels/Labels which pass `t('SIDEBAR.CHANNELS')` etc.).

### Task 5 — ConversationCard chip  [DONE]
- `ConversationCard.vue`: imported `PilotSparkleIcon`; added `participatingAiAgents = computed(() => chatMetadata.value.pilot_assistants || [])`; added `participatingAiAgents.length` to `showMetaSection`; rendered one chip per agent in the meta row as a flex sibling immediately before `<CardStatusLabel>` (sparkle icon + truncated name, Tailwind-only, `bg-n-alpha-2` pill, `title` = agent name). Not added to CardLabels; distinct from business labels.

### i18n  [DONE]
- Added `"AI_AGENTS": "AI Agents"` to the `SIDEBAR` block in `app/javascript/dashboard/i18n/locale/en/settings.json` (the `SIDEBAR.*` keys live in settings.json — there is NO sidebarItems.json in this repo; CHANNELS/LABELS/PILOT all live in settings.json under `SIDEBAR`). Inserted right after `SIDEBAR.CHANNELS` (now line ~380). JSON re-validated. English only. Chip uses `title=agent.name` (data-driven, no new string needed).

### Verification status
- `pnpm eslint:fix` ran on all 6 changed JS/Vue files and **completed with exit code 0**. The only lint output was pre-existing warnings in unrelated files (AssignmentPolicy stories/components); no errors or warnings reported for any of the 6 changed files. No commit/push performed.
- NOTE: jbuilder change above (`_assistant.json.jbuilder`) should be run through `rubocop -a` by a human along with the other backend files.
- The 5 OrbStack scenarios in tasks.md §5 remain for a human to run locally (Acme seed, Mira = Pilot::Assistant id=1).

## ORIGINAL TODO (frontend) — superseded by DONE above

### Task 3 — routes + ConversationView + ChatList + API
- `app/javascript/dashboard/routes/dashboard/conversation/conversation.routes.js`: add two routes mirroring `inbox_dashboard` (line 38) — `ai_agent_dashboard` at `accounts/:accountId/ai-agent/:agentId` props `{ pilotAssistantId: route.params.agentId }`, and `ai_agent_inbox_dashboard` at `.../ai-agent/:agentId/inbox/:inboxId` props `{ pilotAssistantId, inboxId: route.params.inboxId }`. Use CONVERSATION_PERMISSIONS.
- `routes/dashboard/conversation/ConversationView.vue` (THE only ConversationView — Options API, 220 lines; `components/ConversationView.vue` does NOT exist): add prop `pilotAssistantId: { type:[String,Number], default:0 }`; in template pass `:pilot-assistant-id="pilotAssistantId"` to `<ChatList>` (sibling to `:conversation-inbox="inboxId"`, ~line 201).
- `components/ChatList.vue` (`<script setup>`): add prop `pilotAssistantId: { type:[String,Number], default:0 }` (props block line 70-78); add to `conversationFilters` computed (line 268-279): `pilotAssistantId: props.pilotAssistantId || undefined,`. Add a `watch(computed(()=>props.pilotAssistantId), ()=>resetAndFetchData())` near other prop watches (line 874-885).
- `api/inbox/conversation.js` `get({...})` (line 9): add `pilotAssistantId` to destructure and `pilot_assistant_id: pilotAssistantId` to params. (Flow: ChatList conversationFilters -> store state.conversationFilters -> ConversationApi.get(params) at actions.js line 51. camelCase keys flow straight through; no actions.js change needed.)

### Task 4 — Sidebar AI Agents group (`components-next/sidebar/Sidebar.vue`)
- Channels group is at ~line 295 (`name: 'Channels'`, children map `sortedInboxes`, icon `h(ChannelIcon, { inbox, class: 'size-[16px]' })`, child `to: accountScopedRoute('inbox_dashboard', { inbox_id })`, `h(ChannelLeaf, { inbox })`). Labels group ~line 313. Insert AI Agents group BETWEEN Channels and Labels.
- Getters: add `const pilotAssistants = useMapGetter('pilot/assistants/getRecords')` (assistants store at store/pilot/assistants/index.js, getters.getRecords = state.records). Need to VERIFY store namespace registration + the fetch action name, and the autopilot inboxes source (memory: `pilot/autopilot/fetchInboxes`). Dispatch fetch in onMounted (~line 176 area where inboxes/labels are fetched). CHECK store/pilot/autopilot/index.js for fetchInboxes + an inboxes getter to map agent->inboxes (pilot_inboxes). If assistant records already include connected inbox ids/names, no autopilot fetch needed (task 1.1).
- Build group: `name: 'AI Agents'` (i18n — see task: SidebarGroup likely renders `name`; check how 'Channels'/'Labels' resolve — they look literal, so 'AI Agents' literal is consistent, but spec wants i18n. Verify SidebarGroup.vue + add en.json key if i18n.), children = customer-facing assistants (those with >=1 connected inbox). Each assistant child `to: accountScopedRoute('ai_agent_dashboard', { agentId: a.id })`, with its own children per connected inbox -> `accountScopedRoute('ai_agent_inbox_dashboard', { agentId:a.id, inbox_id })` using ChannelIcon. HIDE whole group when no customer-facing assistants (wrap in spread `...(pilotAssistants with inboxes ? [{...}] : [])`, same pattern as `...(isAutopilotEnabled.value ? [...] : [])` at line 665).
- Same visibility as Channels; NO feature flag.

### Task 5 — ConversationCard chip (`components/widgets/conversation/ConversationCard.vue`)
- Import `PilotSparkleIcon` from `dashboard/components-next/pilot/PilotSparkleIcon.vue` (SVG, no props, uses currentColor — size via class).
- Add computed `participatingAiAgents = computed(() => props.chat.meta?.pilot_assistants || [])`.
- In meta row (template ~line 327, sibling to `<CardStatusLabel>`), render one chip per agent: PilotSparkleIcon + `agent.name`. Always-on/data-driven (like CardStatusLabel). Keep distinct from labels; do NOT add to CardLabels. Ensure `showMetaSection` (line 118) still renders row when only chip present (it may need OR participatingAiAgents.length) — verify layout stays stable.
- i18n: any aria/title strings -> en.json.

## i18n (Task 4.1)
- English only. Frontend en.json. Decide AI Agents label literal vs key after checking SidebarGroup.vue.

## Verification (Task 5 in tasks.md) — OrbStack container mode, Acme seed, Mira = Pilot::Assistant id=1
1. Mira on Web+WhatsApp -> one AI Agents entry, two channel children.
2. Select Mira -> only convs with Mira-authored messages.
3. Select Mira WhatsApp child -> WhatsApp + Mira-authored only.
4. Conv without AI participation -> no chip.
5. No labels created/modified.
Run: `pnpm eslint:fix` (JS), `docker compose exec rails bundle exec rubocop -a app/finders/conversation_finder.rb app/models/conversation.rb`.

## Env note
Tool-output channel was lagging badly (results flush 1-2 turns late, sometimes empty). Edits via Edit/Write apply reliably to disk; verify with `git --no-pager diff`. `components/ConversationView.vue` does NOT exist — earlier hallucinated; the real file is under routes/.
