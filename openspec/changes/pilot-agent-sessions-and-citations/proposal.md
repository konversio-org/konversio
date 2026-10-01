## Why

When a Pilot autopilot run answers (or hands off) a customer conversation, nothing durable records what the AI actually did: which model produced the reply, which FAQs, documents, and scenarios were consulted, and which sources the customer was pointed at. Operators cannot audit an AI reply after the fact, cannot answer "why did the assistant say that?", and cannot inspect the generation path of a specific message from the dashboard.

Upstream Chatwoot addressed this in the v4.14–v4.18 release line (Enterprise tier) with per-run session records linked to the resulting message, structured AI replies that carry source citations resolved to trusted customer-visible URLs, and a session detail API backing an agent-facing inspection view. Konversio needs the same operational capability, re-expressed for the MIT core tree under the `Pilot::` namespace.

## What Changes

- Add a `pilot_agent_sessions` table that records each completed Pilot AI run and links it to the conversation (or copilot thread) it ran on and to the message it produced.
- Record per-run knowledge usage on the session: FAQs offered to the model, FAQs actually used, documents consulted, documents actually cited to the customer, and scenarios that participated in the run — plus the model identifier and the run's turn context.
- Capture sessions from the autopilot reply pipeline (and, where applicable, the copilot pipeline) immediately after a successful run delivers a customer-facing reply or a handoff, in a way that can never block or roll back message delivery.
- Extend Pilot AI responses with an optional structured form: an ordered list of reply parts, each carrying the numeric indexes of the knowledge sources it relies on. When citations are enabled on the assistant, cited indexes are resolved server-side to trusted, customer-visible source URLs and rendered into the outgoing message as numbered links. Source URLs are always taken from server-side records, never from model-generated text.
- Persist the structured reply parts on the resulting message's additional attributes so the generation path can be inspected later.
- Add a session detail API endpoint that, given a message, returns its AI run session: model, usage, turn context, cited sources (with links), used FAQs, and participating scenarios — authorized by the viewer's permission to see the conversation.
- Surface the session detail in the dashboard on AI-authored messages so agents can inspect which sources and steps produced a given reply.

## Capabilities

### New Capabilities

- `pilot-agent-sessions`: Durable per-run session records linking Pilot AI runs to conversations and resulting messages, with knowledge-usage attribution (FAQs, documents, scenarios) and run context.
- `pilot-response-citations`: Structured Pilot replies whose parts cite knowledge sources by index, resolved server-side to trusted customer-visible URLs and rendered as numbered links in the customer-facing message.
- `pilot-session-detail-api`: Session detail endpoint and dashboard inspection surface that show, for a given AI-authored message, the model, turn context, cited sources, used FAQs, and scenarios behind it.

### Modified Capabilities

None.

## Impact

- New `pilot_agent_sessions` table and `Pilot::AgentSession` model (core tree, `app/models/pilot/`), with associations from `Account` and `Pilot::Assistant`.
- Autopilot inference pipeline (`Pilot::AutopilotInferenceJob` / `Custom::Pilot::AutopilotService`) gains a post-delivery session capture step; copilot reply generation gains the same where structured replies are supported.
- `Pilot::Assistant` gains citation-resolution helpers gated on its citation config; `Pilot::Document` / `Pilot::AssistantResponse` gain a customer-visible source URL contract.
- Outgoing AI messages gain structured reply parts in `additional_attributes`.
- New account-scoped API route under the existing `pilot` namespace (`config/routes.rb`), controller under `app/controllers/api/v1/accounts/pilot/`, and a Jbuilder view.
- Dashboard: new API client and store module under `app/javascript/dashboard/api/pilot/` and `app/javascript/dashboard/store/`, plus an inspection affordance on AI-authored message bubbles (`components-next/message/`). English i18n only.
