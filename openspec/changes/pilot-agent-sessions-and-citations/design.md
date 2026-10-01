## Context

Upstream Chatwoot shipped this feature set in its Enterprise tier across the v4.14–v4.18 line (released as part of v4.18.0): an `agent_sessions` table (migration `20260709091147` with follow-up additions dated `20260804`/`20260806`), a session capture service invoked from the assistant response pipeline, structured "response parts" carrying citation indexes, resolution of those indexes to trusted customer-visible document URLs, a per-message session detail endpoint, and a dashboard popover showing an AI message's sources and run steps.

**License axis: EE → requirements-level clean-room.** All upstream reference material (model, migration, capture service, response-parts renderer, controller, Jbuilder view, prompt snippet, Vue popover) is Enterprise-edition code. It was consulted for understanding only. Everything in this change is specified as functional requirements in original wording and must be implemented from this spec, not ported. In particular, the implementation must not copy or lightly reword upstream prompt text, UI copy, regexes, or internal naming. Consistent with the standing IP-audit guidance, the result is characterized as an independently re-expressed capability of Konversio's Pilot AI layer.

Konversio-side anchors (all core tree, MIT):

- Pilot assistants already carry citation-related config (`feature_citation`, `citation_behavior`) on `pilot_assistants.config` — see `app/models/pilot/assistant.rb`. The existing `citation_behavior` toggle governs an older, simpler behavior (whether the documentation-search tool surfaces `Source:` lines for PDF-origin matches); the structured citations specified here are an additional, richer mechanism and the two must coexist coherently.
- The autopilot pipeline is `Pilot::AutopilotInferenceJob` → `Custom::Pilot::AutopilotService` (`app/jobs/pilot/autopilot_inference_job.rb`), which differs structurally from upstream's captain_v2 runner — the capture hook point and available run-result shape must be mapped onto Konversio's pipeline.
- Copilot state lives in `copilot_threads` / `copilot_messages` tables with `Pilot::CopilotThread` / `Pilot::CopilotMessage` models.
- Pilot domain services live in `lib/pilot/`; controllers in `app/controllers/api/v1/accounts/pilot/`; the dashboard already has `app/javascript/dashboard/api/pilot/` API clients.
- Konversio has no credit/billing metering (the EE billing stack was removed). Upstream's per-session credit field has no direct equivalent.

## Goals / Non-Goals

**Goals:**

- Persist one session record per completed Pilot AI run, linked account-scoped to its assistant, its subject (conversation or copilot thread), and its result message.
- Attribute knowledge usage per run: offered FAQs, used FAQs, consulted documents, cited documents, participating scenarios.
- Store enough run context (the current turn's message/tool history) to reconstruct what the model saw and did.
- Deliver customer-facing AI replies assembled from structured parts whose citation indexes resolve to trusted, customer-visible source URLs rendered as numbered links.
- Guarantee that citation URLs shown to customers always come from server-side records, never from model output.
- Expose a per-message session detail API, authorized by conversation visibility, and a dashboard inspection surface on AI-authored messages.
- Capture must be failure-isolated: a session-recording bug must never affect reply delivery.

**Non-Goals:**

- Recording failed runs (sessions are written for successful runs that produced a customer-facing reply or handoff; error-session semantics are undefined and deferred).
- Copilot session capture beyond what the copilot pipeline can already supply — assistant (autopilot) sessions are the primary target; copilot support is specified but may ship second.
- Any credit, billing, or quota metering.
- Analytics/reporting rollups over sessions (deflection, usage dashboards) — the table is designed so these are possible later, but no reporting UI is in scope.
- Changing the existing `citation_behavior` documentation-search toggle semantics.
- Widget-side rendering changes beyond what the existing markdown message renderer already does with numbered links.

## Decisions

### One polymorphic session table, `pilot_agent_sessions`

A single `pilot_agent_sessions` table with a session kind discriminator and polymorphic `subject` / `result` references. For autopilot runs the subject is the `Conversation` and the result is the produced `Message` (including, on handoff, the private handoff note when one was recorded during the run); for copilot runs the subject is the copilot thread and the result the copilot message. The kind discriminator constrains which subject/result types are valid.

Alternatives considered:

- Separate tables per kind. Doubles the API and capture machinery for no isolation benefit; the two kinds share every attribute.
- Linking only to conversations, not messages. Loses the ability to answer "which sources produced *this* reply" when a conversation has many AI replies.

Rationale: one table keeps capture, validation, and the detail API uniform, and polymorphic result linkage is what makes the per-message inspection surface possible.

### Konversio naming, not upstream naming

The model is `Pilot::AgentSession`; new code lands in `app/models/pilot/agent_session.rb`, a new capture service under `lib/pilot/` (Konversio's existing home for Pilot domain services), a structured-reply value object under `lib/pilot/`, a controller under `app/controllers/api/v1/accounts/pilot/`, and dashboard modules under the existing `pilot` API/store directories. Upstream class, method, and constant names are deliberately not reused; the tasks file names concrete proposed paths, which the implementer may refine but must keep free of upstream identifiers.

### Failure-isolated, post-delivery capture

Session capture runs after the customer-facing message (or handoff note) has been created, outside the delivery transaction, and swallows its own errors (log + exception tracker). Only successful runs are recorded.

Alternatives considered:

- Capture inside the message-creation transaction. A session bug would roll back a delivered reply — unacceptable coupling.
- Capture failures as sessions too. Deferred: the semantics of a "failed run" session (partial context, no result message) need their own design.

Rationale: observability must never jeopardize the customer interaction it observes.

### Structured reply parts with index-based citations

When citations are enabled on the assistant, the model is asked (via prompt instructions written fresh for Konversio) to return its reply as an ordered list of parts, each with the numeric indexes of the knowledge results it relies on. The generation pipeline keeps a run-state mapping from those indexes to knowledge source IDs. Plain (non-citation) replies degrade gracefully to a single part with no citations.

Alternatives considered:

- Letting the model embed URLs inline. Rejected outright: model-supplied URLs can be hallucinated; every customer-visible citation URL must resolve from server-side knowledge records.
- Citation markers as inline footnote syntax in a single text blob. Harder to validate, strip, and re-render than a structured parts list.

Rationale: index-based indirection keeps the trust boundary on the server and makes the parts list storable on the message for later inspection.

### Trusted URL resolution and eligibility filtering

Citation URLs are resolved server-side from the knowledge documents behind the cited indexes. A URL is eligible only when the source document is flagged customer-visible, its link is a well-formed `http(s)` URL, and it is not an uploaded-file placeholder (uploaded PDFs have no customer-resolvable external link). Ineligible indexes are silently dropped — the reply text stands without a link. Display numbers are assigned per unique URL in first-appearance order and reused for repeats. Session capture records as "cited documents" exactly those documents whose indexes were both used in the delivered parts and eligible.

### Turn-scoped run context

The stored run context is trimmed to the current turn: the latest customer message and everything after it (assistant replies, tool calls and results, scenario hops), with any rich content objects normalized to a serializable form. Full multi-turn history is not stored.

Rationale: the turn is the unit an operator inspects; storing the whole conversation history per session would duplicate data the conversation already holds and grow the table unboundedly.

### Session detail API keyed by message

The detail endpoint lives under the account-scoped `pilot` namespace and is addressed by the ID of the AI-authored message (matching how the dashboard thinks about the inspection surface). It returns 404 when no session exists for the message and authorizes via the viewer's permission to view the parent conversation. Citation links are included only when they are `http(s)`; other links are omitted so the UI renders them as plain text. Used FAQs are limited to approved, user-authored FAQ entries.

### No credits field

Konversio has no metering currency. The session schema carries a nullable numeric usage-charge field only if Konversio's run pipeline already exposes a per-run usage metric worth recording.

- needs investigation: whether `Custom::Pilot::AutopilotService` (or the RubyLLM layer) exposes per-run token/usage numbers at the capture point; if nothing reliable exists, omit the field rather than inventing a metering concept.
- needs investigation: the exact run-result/context object available at the capture point in Konversio's autopilot and copilot pipelines, and where the index→source run-state mapping should live there.

## Risks / Trade-offs

- **Clean-room drift** -> The spec fixes behavior and data shape, not expression; reviewers should compare implementation against this spec, not against upstream code.
- **Prompt change risk** -> Asking for structured parts changes generation behavior; the fallback to a single plain part must be exercised for assistants with citations disabled and for models that ignore the structure.
- **Table growth** -> Turn context is bounded per session, but high-volume autopilot accounts will accumulate rows; retention/archival is a future decision, not in scope.
- **Two citation systems coexisting** -> The legacy `citation_behavior` toggle and the new structured citations must not double-render sources; the spec requires the new mechanism to own link rendering for structured replies.

## Migration Plan

1. Add the table and model first (additive, no data migration).
2. Wire capture into the autopilot pipeline behind the existing `pilot_autopilot` feature flag; sessions simply don't exist for messages that predate the change (the API returns 404 and the UI shows an empty state).
3. Roll out structured replies per assistant via its citation config; assistants without it keep today's plain-text path.
4. Rollback: stop calling capture and hide the UI affordance; existing rows are harmless and the detail API 404s.

## Open Questions

- Should copilot sessions ship in the same release or follow? The schema supports both; the copilot capture hook is the uncertain part.
- Should the dashboard expose run context raw or only as a humanized steps timeline? The v1 UI shows a steps timeline (tool calls and scenario hops) and deliberately does not echo message bodies or raw tool output.
