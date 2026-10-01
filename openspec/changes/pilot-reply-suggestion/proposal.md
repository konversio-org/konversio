## Why

Konversio's Pilot Copilot drawer today only supports free-form chat: an agent opens the drawer, types a question, and the assistant answers. Upstream Chatwoot (EE) shipped a dedicated **reply-suggestion mode** for this surface: with one click on a conversation whose latest public message is from the customer, the agent gets a ready-to-send draft reply produced by the assistant's AI run pipeline — with conversation-access permission checks, a restricted tool set, and discard semantics when the conversation has moved on by the time generation finishes.

Because the upstream implementation lives in the EE-licensed `enterprise/` overlay that this fork deliberately removed, this change re-expresses the feature as an original functional specification targeting Konversio's MIT core tree (`Pilot::` namespace, `app/`, `lib/`, `custom/`). No upstream prompt text, UI copy, or class naming is carried over.

## What Changes

- Extend the Pilot copilot thread creation endpoint (`POST /api/v2/accounts/:account_id/pilot/copilot_threads`) with an optional `request_type` parameter. The default remains free-form chat; `request_type=reply_suggestion` creates a thread whose assistant response is a suggested reply to the conversation the agent is viewing.
- Validate at request time that the requesting agent may access the referenced conversation; reply-suggestion requests for inaccessible conversations are rejected as not-found (no existence leak).
- Add a background job + service that generates the suggested reply through the same ai-agents SDK runner pipeline used by Copilot chat (`Custom::Pilot::CopilotService`), but with:
  - a draft-oriented system prompt contract (new original prompt; requirement specified, wording owned by Konversio);
  - a restricted tool set: the assistant's knowledge/FAQ lookup plus account custom HTTP tools that are individually flagged as available for reply drafting; all other tools are withheld;
  - idempotent, locked persistence: exactly one assistant response per reply-suggestion thread;
  - discard semantics: if the conversation's latest public message changed (or is no longer an incoming customer message) by the time the run completes, persist a localized "no longer applicable" response instead of a draft, without consuming a response credit;
  - failure semantics: on generation error, retry with backoff; after the final attempt, persist a localized failure response.
- Add an `available_for_reply_drafting` flag to `pilot_custom_tools` so account HTTP tools opt in to the draft-run tool set.
- Frontend: surface a "suggest a reply" quick action in the Pilot Copilot drawer when the agent is viewing a conversation whose latest public message is incoming; render the resulting draft with an insert-into-reply-editor action; reset the active copilot thread when the viewed conversation changes.

## Capabilities

### New Capabilities

- `pilot-copilot-reply-suggestion`: One-click draft reply generation in the Pilot Copilot drawer, reusing the AI run pipeline with a restricted tool set, idempotent persistence, and discard/failure semantics.
- `pilot-copilot-conversation-access`: Permission resolution that determines which conversations a given agent may reference from Copilot surfaces, enforced both at request time and again at persistence time.

### Modified Capabilities

None. (The existing Pilot copilot chat behavior is unchanged when `request_type` is absent.)

## Impact

- `app/controllers/api/v2/accounts/pilot/copilot_threads_controller.rb` (new `request_type` param, access pre-check, job dispatch branching)
- New job under `app/jobs/pilot/` and new service under `custom/app/services/custom/pilot/` (draft generation, locked persistence, discard/failure)
- `pilot_custom_tools` table (new boolean column, migration required) and `Pilot::CustomTool`
- `copilot_threads` / `copilot_messages` tables are reused as-is; the draft flag travels in the existing `message` JSONB payload (no new tables)
- Frontend: `app/javascript/dashboard/api/pilot/copilot.js`, the Pilot Copilot drawer components under `app/javascript/dashboard/components-next/pilot/copilot/`, and the reply editor insert path
- English frontend i18n only for new labels and localized fallback responses
