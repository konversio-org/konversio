## Tasks

### Backend

1. - [ ] **Migration** — add `available_for_reply_drafting` boolean column to `pilot_custom_tools` (default `false`, null: false); expose it on `Pilot::CustomTool` (`app/models/pilot/custom_tool.rb`) and in the custom-tools API payload.
2. - [ ] **Conversation access module** — add a reusable `Pilot::Copilot::ConversationAccess`-style concern (e.g. under `custom/app/services/custom/pilot/` or `app/controllers/concerns/`) that resolves "conversations accessible to this agent in this account" by reusing `Conversations::PermissionFilterService`; investigate and wire team/custom-role scoping if the platform has it (see design.md "Permission resolution").
3. - [ ] **Controller** — in `app/controllers/api/v2/accounts/pilot/copilot_threads_controller.rb`: permit `request_type`; when it equals `reply_suggestion`, require `conversation_id`, resolve the conversation through the access concern and raise not-found when inaccessible, then dispatch the new draft job instead of `Pilot::CopilotInferenceJob`. Default path unchanged.
4. - [ ] **Job** — new `app/jobs/pilot/copilot_reply_suggestion_job.rb`: delegates to the service; retries the service's generation error with backoff (3 attempts, ~3s wait) and persists the failure response after the final attempt.
5. - [ ] **Service** — new `custom/app/services/custom/pilot/copilot_reply_suggestion_service.rb` following the structure of `Custom::Pilot::CopilotService`: bind thread (scoped to account + user), verify conversation access, short-circuit when an assistant message already exists, capture the target latest public message, skip early when it is not incoming, run the ai-agents SDK agent with draft instructions + restricted tools, persist under a thread lock with the access/target-message rechecks, record response usage only on a persisted draft.
6. - [ ] **Draft instructions asset** — write the new original draft-oriented system prompt (functional contract in `specs/pilot-copilot-reply-suggestion/spec.md`; do NOT copy upstream wording); store it as a Konversio-owned prompt template consistent with how other Pilot prompts are loaded.
7. - [ ] **Restricted tool wiring** — build the draft-run tool list: knowledge/FAQ lookup plus enabled `Pilot::CustomTool` records flagged `available_for_reply_drafting` (adapted via `Pilot::Tools::AgentToolAdapter` / `Pilot::RubyLlmToolAdapter` as appropriate), then pass through `Custom::Pilot::CopilotToolPermissionFilter` before the runner is built.
8. - [ ] **Message payload** — persist successful drafts as `Pilot::CopilotMessage` (`message_type: :assistant`) with `content` = draft text and a `reply_suggestion: true` flag in the `message` JSONB; discarded/failure fallbacks are plain localized content messages.
9. - [ ] **I18n** — add English backend strings for the discarded and failure fallback responses in `en.yml` (original wording), resolved against the user's UI locale with account-locale fallback.
10. - [ ] **Tracing** — wrap the run in `Custom::Pilot::TraceSpan` with the account/assistant/conversation attributes used by the copilot inference service, plus discarded/credit-used outcome attributes.

### Frontend

11. - [ ] **API client** — extend `app/javascript/dashboard/api/pilot/copilot.js` `createThread` to pass `request_type` through.
12. - [ ] **Quick action** — in the Pilot Copilot drawer empty state (`app/javascript/dashboard/components-next/pilot/copilot/` components), add a "suggest a reply" quick action on conversation routes, shown only when the selected conversation's latest public message is incoming; it dispatches thread creation with `request_type: 'reply_suggestion'`.
13. - [ ] **Draft rendering** — render assistant messages flagged `reply_suggestion` in the drawer with an insert-into-reply-editor action (rich-editor insert path) and distinct draft styling; discarded/failure messages render as plain assistant text without the insert action.
14. - [ ] **Conversation switching** — reset the active copilot thread when the viewed conversation changes so a draft thread from conversation A is never shown against conversation B.
15. - [ ] **I18n** — add English frontend strings for the quick action and draft affordances in `en.json` (original wording; no upstream copy).

### Validation

16. - [ ] **Service specs** — `spec/services/custom/pilot/copilot_reply_suggestion_service_spec.rb`: happy path draft persisted with flag; idempotent second run returns existing response; inaccessible conversation → failure response; non-incoming latest message → discarded response without usage; target message changed mid-run → discarded; generation error → job retry then failure response after final attempt; restricted tool list excludes non-flagged custom tools.
17. - [ ] **Controller/request specs** — `request_type=reply_suggestion` without accessible conversation returns 404; without `conversation_id` returns 4xx; absent `request_type` behaves exactly as before; thread scoping still hides other agents' threads.
18. - [ ] **Frontend specs** — quick action visibility follows latest-public-message type; draft message renders insert action; thread reset on conversation switch.
19. - [ ] **Manual smoke test** — on a conversation whose last message is incoming, trigger the quick action; verify a draft appears in the drawer, inserts into the reply editor, and that replying to the conversation first (making the last message outgoing) before triggering yields the discarded state.

## Dependencies / Order

Tasks 1 and 2 are independent and unblock the rest. Task 3 depends on 2 and 4. Tasks 4–5 depend on 2; 5 also depends on 1 and 6–7. Tasks 8–10 land inside 5. Frontend tasks 11–15 depend on 3 (API shape) and can start once the payload contract (8) is fixed. Tasks 16–19 validate the whole chain.
