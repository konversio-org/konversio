## Context

This change is the **EE → requirements-level clean-room** axis. The upstream implementation lives in Chatwoot's `enterprise/` overlay (`enterprise/app/...captain/faq_suggestion*`, `enterprise/app/services/captain/llm/conversation_faq*`, migration `20260713184351`), which is EE-licensed and was deliberately removed from this fork. Upstream code was read for behavioral understanding only. Everything below is an original functional specification targeting Konversio's MIT core tree: `Pilot::` namespace, `pilot_` table prefixes, no `enterprise/` paths. Per the standing audit guidance, Pilot is characterized as an independently re-expressed AI integration layer — no upstream prompt text, UI copy, category taxonomies, regexes, or class naming is carried over.

Konversio already has its own resolve-time mining pipeline: `PilotResolveListener` enqueues `Pilot::Conversations::FaqMiningJob` on `conversation_resolved` when the assistant's `feature_faq` config flag is on; the job builds a customer/human-agent transcript, short-circuits when no human reply exists, extracts pairs via `Custom::Pilot::FaqMiningService`, dedups them via `Custom::Pilot::FaqMiningDeduper` (cosine distance < 0.3 against the whole response corpus), and persists survivors as `Pilot::AssistantResponse` rows with `status = pending`. This change replaces the *persistence* stage of that pipeline with a suggestion/observation staging layer and adds the review surface on top.

## Goals / Non-Goals

**Goals:**

- Stage mined FAQ candidates as reviewable `Pilot::FaqSuggestion` records instead of writing them directly into the knowledge base.
- Record every mined candidate as a `Pilot::FaqObservation` tied to its source conversation, so reviewers can see where a suggestion came from.
- Deduplicate across conversations: repeat sightings of the same question attach to the existing open suggestion and raise its source count rather than creating a new record.
- Make dismissals sticky: a candidate matching a dismissed suggestion is silently discarded on future sightings.
- Avoid re-mining what is already known: a candidate matching an approved knowledge entry is discarded.
- Provide an atomic approve workflow that converts a suggestion (optionally with reviewer edits) into an approved `Pilot::AssistantResponse`.
- Scope visibility by conversation permissions: non-admin agents only see suggestions whose observations touch conversations they can access.
- Ship a review UI in the Pilot FAQs area with an open-count entry point, list, search, source inspection, edit, approve, and dismiss.

**Non-Goals:**

- Changing how candidates are extracted from transcripts (the existing generation service and its prompt stay as-is; only persistence changes).
- Porting upstream's FAQ generation prompts, lookup tools, citation tracking, or agent-session plumbing (those are separate upstream work items and are EE-expression in any case).
- Bulk review operations (bulk approve/dismiss) — single-record actions only in v1.
- Elasticsearch-backed suggestion search (SQL pattern matching is sufficient at this scale).
- Analytics/reporting over suggestions (acceptance rates, deflection estimates).
- Reopening approved or dismissed suggestions — both states are terminal in v1.

## Decisions

### Two-table staging model: suggestions + observations

A `Pilot::FaqSuggestion` is the reviewable unit (one per distinct FAQ candidate per assistant and language); a `Pilot::FaqObservation` is the per-conversation sighting. One conversation contributes at most one attached observation per suggestion (enforced by a partial unique index on `(conversation_id, faq_suggestion_id)` where the suggestion reference is present). Observations that matched existing knowledge or a dismissed suggestion are stored with a discarded status and no suggestion reference, giving an audit trail without queue noise.

Alternatives considered:
- Keep writing pending `Pilot::AssistantResponse` rows directly (status quo). Rejected: no source tracking, no sticky dismissals, duplicates across conversations.
- A single denormalized table with a JSON array of source conversation ids. Rejected: loses per-sighting generated text, complicates permission-filtered source previews, and makes the "one observation per conversation per suggestion" invariant harder to enforce.

Rationale: the two-table shape cleanly separates the review unit from the evidence, and the partial unique index gives idempotent re-mining of the same conversation for free.

### Two-stage matching: embedding shortlist, then LLM equivalence judgment

For each mined candidate, embed `"<question>: <answer>"`, take the nearest neighbors (cosine distance below 0.3, small fixed limit) from three pools in order — approved knowledge entries, dismissed suggestions in the same language, open suggestions in the same language — and for each shortlisted record ask a lightweight LLM judgment whether the pair is truly the same FAQ (boolean verdict). The first pool with a confirmed match decides the route: discard, discard, or attach. Nearest-neighbor queries inside a transaction disable index scans locally so that relation filters (status, language) cannot cause the approximate vector index to miss true matches.

Alternatives considered:
- Pure embedding threshold (current `Custom::Pilot::FaqMiningDeduper` behavior). Rejected as the sole signal: a fixed distance cutoff both merges distinct FAQs that merely share a topic and misses genuine rephrasings near the boundary; upstream reached the same conclusion and layered a semantic check on top.
- LLM-compare every candidate against every record. Rejected: cost and latency scale with corpus size.

Rationale: embeddings keep the comparison set tiny; the LLM verdict makes merge/keep-distinct decisions that wording-level similarity cannot, and a boolean verdict with strict parsing keeps failures detectable.

### Approval is a locked, single-operation conversion

Approval runs inside a row lock: it refuses non-open suggestions (raising not-found for idempotent retry safety), applies any reviewer edits, creates the approved `Pilot::AssistantResponse` from the final question/answer, and flips the suggestion to approved. Dismiss likewise locks and refuses non-open records. Editing (`update`) is also restricted to open suggestions, so a record under review can never be modified after a decision.

Alternatives considered:
- Approval by flipping the suggestion's own status and having the knowledge search union in approved suggestions. Rejected: two knowledge stores to search, embed, and maintain; conversion keeps `pilot_assistant_responses` as the single searchable corpus.
- Optimistic concurrency without locks. Rejected: concurrent approve/dismiss races are realistic when several reviewers work the queue.

Rationale: conversion keeps retrieval paths unchanged, and the lock makes the open → approved/dismissed transition exactly-once.

### Permission-aware visibility via observations

Administrators see all suggestions in the account. Non-admin agents see only suggestions that have at least one observation on a conversation visible to them under the existing conversation permission filter (`Conversations::PermissionFilterService`). The detail endpoint's source-conversation preview applies the same filter per observation. Policy-level, any account member may use the endpoints; data-level scoping does the real restriction.

Alternatives considered:
- Admin-only review. Rejected: teams that distribute FAQ curation across agents would be blocked.
- Inbox-level ownership on suggestions. Rejected: suggestions are assistant-scoped, and assistants span inboxes; conversation-derived scoping already reflects what an agent may see.

Rationale: reusing the conversation permission filter means no new ACL model and no leakage of conversation-derived content to agents who cannot see the underlying conversations.

### Language is first-class on both tables

Suggestion matching and creation are partitioned by a normalized language code derived from the account locale (hyphen/underscore variants collapsed to their primary subtag). A conversation only ever contributes to suggestions in its own language, and dismissed-suggestion suppression is per-language, so a dismissal in one language does not suppress the equivalent FAQ mined in another.

### Generation-quality gating (v4.14.0 FAQ improvements, requirements level)

The mining prompt contract MUST require, functionally: answers sourced only from human support agent statements (never customer messages, never the assistant's own prior output, never the injected business context); only durable, publicly reusable knowledge (no account-specific, order-specific, or one-off case handling); no private identifiers or customer-specific facts in generated text; and an explicit empty result when the conversation yields nothing suitable. Upstream v4.14.0 tightened its prompts along these lines; we specify the requirement, not their wording. needs investigation: whether Konversio's existing `Custom::Pilot::FaqMiningService` prompt already enforces each of these gates, and which gaps need prompt edits — that review is part of implementation, not this spec.

## Risks / Trade-offs

- **LLM equivalence calls add cost per mined candidate** -> bounded by the embedding shortlist (a handful of comparisons per candidate, only when near matches exist); failures of the judgment call are logged and treated as "not the same" is NOT acceptable — a failed judgment must surface as a job error rather than silently creating duplicates (see spec requirement on judgment failures).
- **Migration changes mining semantics for existing installs** -> candidates that previously became pending responses now become suggestions; existing pending responses are untouched and remain reviewable through the existing responses UI. No data migration of old pending rows.
- **Observation growth** -> one row per mined conversation that produced a candidate; discarded observations are retained for audit in v1. Retention/pruning is a future concern.
- **Review queue discoverability** -> the open-count banner on the FAQs page is the primary entry point; the count must stay cheap (single filtered count query, no N+1).

## Migration Plan

1. Additive migration: create `pilot_faq_suggestions` and `pilot_faq_observations` with indexes (including the pgvector ivfflat index on suggestion embeddings, cosine ops).
2. Switch `Pilot::Conversations::FaqMiningJob` persistence to the suggestion routing path; existing pending `Pilot::AssistantResponse` rows are unaffected.
3. Ship the review API and UI together; the feature remains gated by the existing `feature_faq` assistant config flag plus the account `pilot` / `pilot_autopilot` feature flags already consulted by `PilotResolveListener`.
4. Rollback: revert the job persistence path to direct pending-response creation; drop the new tables in a follow-up migration. No production data outside the two new tables is mutated.

## Open Questions

- Should `Custom::Pilot::FaqMiningDeduper` be deleted once its role is absorbed by the suggestion routing, or retained for document-based FAQ generation flows (if any still use it)? needs investigation: confirm all current callers before removal.
- The upstream list page sizes at 25 records per page and previews up to 50 source conversations per suggestion; these are adopted as defaults — needs investigation only if Pilot UX conventions differ.
- Whether the open-count entry point should live on the existing FAQs page header (upstream pattern) or as a separate sidebar entry under Pilot — default follows the upstream pattern on `PilotFaqsPage.vue` unless the Pilot navigation structure argues otherwise during implementation.
