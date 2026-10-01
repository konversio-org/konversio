## Context

This change is the **EE → requirements-level clean-room** axis. The upstream implementation lives in Chatwoot's EE-licensed `enterprise/` overlay, which was deliberately removed from this fork. The following upstream files (v4.13.0 → v4.18.0 diff) were read for behavioral understanding only:

- `enterprise/app/controllers/api/v1/accounts/captain/copilot_threads_controller.rb` (the `request_type` branch and request-time access check)
- `enterprise/app/jobs/captain/copilot/reply_suggestion_job.rb` and `enterprise/app/services/captain/copilot/reply_suggestion_service.rb` (job retry policy, idempotent locked persistence, discard/failure responses)
- `enterprise/app/services/captain/copilot/conversation_access.rb` (permission resolution)
- `enterprise/app/services/captain/assistant/agent_runner_service.rb` (the reply-suggestion source that swaps the prompt template and filters the tool list)
- `enterprise/app/services/captain/llm/prompts/copilot_reply_suggestion.liquid` (existence and role of the draft prompt only — its text was NOT carried over)

Everything below is an original functional specification targeting Konversio's MIT core tree: `Pilot::` namespace, no `enterprise/` paths, `pilot_` prefixes for any new schema. Per the standing audit guidance, Pilot is characterized as an independently re-expressed AI integration layer — no upstream prompt text, UI copy, label taxonomies, regexes, or class naming is reproduced.

Konversio already has the surrounding pieces this change plugs into: `Pilot::CopilotThread` / `Pilot::CopilotMessage` (backed by the existing `copilot_threads` / `copilot_messages` tables), `Pilot::CopilotInferenceJob`, and `Custom::Pilot::CopilotService`, which runs the ai-agents SDK runner with per-tool permission filtering (`Custom::Pilot::CopilotToolPermissionFilter`). The reply-suggestion mode is a sibling run mode over the same pipeline, not a parallel stack.

## Goals / Non-Goals

**Goals:**

- Let an agent request a suggested reply for the conversation they are viewing, from the Pilot Copilot drawer, in one action.
- Enforce conversation access permission checks both when the request is accepted and again before the draft is persisted.
- Generate the draft through the existing ai-agents SDK runner pipeline with a restricted tool set (knowledge lookup + opt-in custom HTTP tools only).
- Guarantee exactly one assistant response per reply-suggestion thread, even under job retries and races.
- Discard the draft gracefully when the conversation has moved on (a newer public message exists, or the latest public message is no longer an incoming customer message) without consuming a response credit.
- Persist a localized failure response when generation ultimately fails, so the drawer never hangs.
- Let account custom HTTP tools opt in to draft-run availability via a flag on `pilot_custom_tools`.

**Non-Goals:**

- Porting the upstream draft prompt text (a new original Konversio prompt is written at implementation time against the functional contract in the spec).
- Auto-sending drafts or any customer-facing autopilot behavior; the draft is always reviewed and sent by a human.
- Follow-up refinement of a draft inside the same thread (the existing single-shot `Pilot::ReplySuggestionService` used by the editor already covers refinement; converging the two paths is a future decision).
- Response-usage quota enforcement / limit messaging beyond recording usage for successful drafts.
- Porting upstream's OpenTelemetry attribute layout verbatim (Konversio's existing `Custom::Pilot::TraceSpan` conventions apply).
- Changing the free-form Copilot chat mode.

## Decisions

### One thread-creation endpoint with a `request_type` discriminator

The existing `POST /api/v2/accounts/:account_id/pilot/copilot_threads` gains an optional `request_type` parameter. Absent (or any value other than the reply-suggestion token) means the current free-form chat behavior, dispatched to `Pilot::CopilotInferenceJob`. The reply-suggestion token requires `conversation_id`, validates access synchronously, and dispatches the new draft job.

Alternatives considered:
- A separate endpoint (e.g. `POST .../pilot/reply_suggestions`). Rejected: the result must live in a copilot thread so the drawer renders it with the existing message list, events, and insert-into-editor plumbing; a second resource would duplicate that surface.
- Overloading the message content (magic phrases). Rejected: implicit, fragile, and impossible to permission-check cleanly.

Rationale: a discriminator on the existing endpoint mirrors how the drawer already creates threads and keeps one code path for thread/message persistence.

### Dedicated job + service reusing the shared runner pipeline

The draft run is executed by a new `Pilot::` job and a new `Custom::Pilot::` service that build an ai-agents SDK agent the same way `Custom::Pilot::CopilotService` does (model resolution, runner, max-turn cap, tracing), but with two deliberate deviations: draft-oriented instructions, and a restricted tool list. The service, not the job, owns all persistence (same separation of responsibilities as the existing copilot inference flow).

Alternatives considered:
- Add a mode flag to `Custom::Pilot::CopilotService` itself. Rejected: that service's contract is "respond to the latest user message in a chat thread"; the draft flow has different inputs (conversation-centric), different discard semantics, and a different single-response invariant. A boolean would fork every method.
- Extend the editor-side `Pilot::ReplySuggestionService` (`lib/pilot/reply_suggestion_service.rb`). Rejected: it is a single-shot formatter call without the agent runner, tool execution, thread persistence, or event dispatch the drawer needs.

Rationale: a sibling service keeps both contracts small and lets each evolve independently while sharing the runner/tooling primitives.

### Restricted tool set: knowledge lookup plus opt-in HTTP tools only

The draft run exposes only (a) the assistant's knowledge/FAQ lookup tool and (b) account custom HTTP tools (`pilot_custom_tools`) whose new `available_for_reply_drafting` flag is set. Every other tool available to Copilot chat (conversation search/get, contact lookup, and any future mutating tool) is withheld from the draft run. The same pre-run permission filter used by Copilot chat (`Custom::Pilot::CopilotToolPermissionFilter`) still applies on top.

Alternatives considered:
- Give the draft run the full chat tool set. Rejected: drafting a customer reply does not need arbitrary account exploration, and a smaller surface reduces prompt-injection blast radius from customer-authored message content, which is exactly what the draft run ingests.
- Make all HTTP tools available by default. Rejected: custom tools can have side effects; opt-in per tool makes the exposure an explicit account decision.

Rationale: least-privilege tool exposure for a run whose primary input is untrusted customer text.

### Access checks at request time AND persistence time

Request time: the controller resolves the referenced conversation through the same visibility rules that govern the conversations list; if the agent cannot see it, the request fails as not-found (404, never 403, so thread/conversation existence is not leaked — consistent with the existing `load_thread` behavior). Persistence time: the service re-verifies access inside the persistence lock before writing the draft, because membership may have changed while the job ran.

Alternatives considered:
- Request-time check only. Rejected: inbox membership can be revoked between enqueue and run; the draft embeds conversation content and must not be written for an agent who lost access.
- Skip the request-time check and let the job fail silently. Rejected: the agent would see a hanging drawer with no feedback.

Rationale: defense in depth with user-visible rejection early and a hard guarantee late.

### Permission resolution follows conversation-list visibility

"Accessible" means what the account's conversation permission model already grants the agent: administrators see all conversations in the account; non-admin agents see conversations permitted by their role, inbox membership, and any team/custom-role scoping the platform applies. The implementation SHOULD reuse the existing permission-filter plumbing (`Conversations::PermissionFilterService` and anything layered on it) rather than inventing a parallel ACL. needs investigation: Konversio's core `Conversations::PermissionFilterService` currently scopes non-admin agents by inbox membership only; upstream additionally honors team membership and custom-role conversation scopes. Whether Konversio has (or wants) team/custom-role conversation scoping for Copilot access must be confirmed at implementation time — the spec requires "same visibility as the conversations list" and does not mandate a specific mechanism.

### Idempotent locked persistence with discard and failure states

Exactly one assistant message is ever written to a reply-suggestion thread. Persistence happens under a database lock on the thread and proceeds only if: no assistant message exists yet, the agent still has access, and the conversation's latest public (non-private) incoming/outgoing message is unchanged since the run started. If the target message changed or the latest public message is no longer an incoming customer message, a localized "suggestion no longer applicable" response is persisted instead of the draft, flagged as discarded, and no response usage is recorded. On generation error the job retries with backoff (three attempts); after the final failure a localized "could not generate" response is persisted so the drawer always settles.

Alternatives considered:
- Persist the stale draft anyway. Rejected: suggesting a reply to a message that has already been answered is actively harmful.
- Delete the thread on discard. Rejected: loses the audit trail and confuses the drawer; a visible discarded state is clearer.
- Unbounded retries. Rejected: the drawer must settle; three attempts matches the surrounding job conventions.

Rationale: the lock + recheck makes the happy path exactly-once, and the two terminal fallback states keep the UI deterministic under every failure mode.

### Draft payload travels in the existing message JSONB

The assistant message for a successful run stores the draft text in `message.content`, plus a boolean flag marking it as a reply suggestion (so the drawer renders the insert-into-editor action and can distinguish drafts from chat answers) and optional generation metadata (e.g. reasoning) where the pipeline provides it. The tolerant `Pilot::CopilotMessage` validation (Hash with `content`, unknown keys allowed) already permits this; no schema change to `copilot_messages`.

Alternatives considered:
- A new `pilot_reply_suggestions` table. Rejected: duplicates thread/message rendering, events, and pagination for no isolation benefit; the draft IS a copilot message.

Rationale: the existing JSONB contract was deliberately made tolerant for exactly this kind of payload extension.

### Draft prompt is a new original Konversio asset

The functional contract for the draft instructions is specified (see spec: reply to the customer's latest incoming message, in the conversation's language, honoring the assistant persona, ready to send without conversational framing), but the wording is written fresh at implementation time. The upstream `copilot_reply_suggestion` prompt text is reference-only and MUST NOT be reproduced or lightly reworded.

## Risks / Trade-offs

- **Two reply-suggestion paths coexist** (editor-side `Pilot::ReplySuggestionService` and the new drawer mode) -> acceptable short-term duplication; the drawer mode is conversation-and-permission-aware while the editor path is a stateless formatter call. Convergence is an explicit future decision, not part of this change.
- **Prompt-injection via customer messages** -> mitigated by the restricted tool set and by instructions that treat conversation content as data, not commands; the draft always passes human review before sending.
- **Discarded drafts waste an LLM run** -> inherent to async generation; bounded by the pre-run target-message check (runs are skipped early when the conversation is already stale) and by not recording usage on discards.
- **Job retries multiply LLM cost on provider outages** -> capped at three attempts with backoff, matching existing job conventions.

## Migration Plan

1. Additive migration: add `available_for_reply_drafting` boolean (default false, not null) to `pilot_custom_tools`.
2. Ship backend (param, access checks, job, service, restricted tool wiring) behind the existing `pilot` + `pilot_copilot` account feature flags.
3. Ship the drawer quick action and draft rendering in the same release.
4. Rollback: stop dispatching the new job and hide the quick action; existing threads/messages remain valid because the draft is an ordinary copilot message. The new column is inert.

## Open Questions

- Should the editor-side "AI assist" reply button and the drawer mode share one generation path eventually? needs investigation: compare `Pilot::ReplySuggestionService`'s refinement loop with the drawer mode's single-shot contract before deciding.
- Which localized fallback strings ship in v1 (discarded / failure) and whether they follow the user's UI locale or the account locale — default: user's UI locale with account-locale fallback, matching surrounding Pilot behavior. needs investigation: confirm an existing locale-resolution helper is reused rather than inventing a new one.
- Whether follow-up chat messages should be accepted on a reply-suggestion thread after the draft lands (upstream allows continuing the thread as chat). Default: allow, routed to the normal chat inference path; confirm during implementation that mixing modes in one thread renders correctly in the drawer.
