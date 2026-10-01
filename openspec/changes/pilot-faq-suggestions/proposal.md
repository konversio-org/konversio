## Why

Pilot's resolve-time FAQ mining (`Pilot::Conversations::FaqMiningJob`) writes mined question/answer pairs directly into `pilot_assistant_responses` with `status = pending`. There is no staging layer: a candidate seen once in one conversation lands in the same review queue as curated knowledge, there is no record of which conversations produced a candidate, repeated sightings of the same question across conversations create nothing useful, and a dismissed candidate can be re-mined from the next similar conversation because the system does not remember the dismissal.

Upstream Chatwoot addressed this across v4.14.0 (FAQ mining quality improvements) and v4.16.2 (FAQ suggestion review API and interface) with a two-table suggestion/observation model: mined candidates become reviewable suggestions, each sighting is recorded as an observation linked to its source conversation, repeat sightings increment a source count instead of duplicating, and approval converts the suggestion into an approved knowledge entry. Konversio needs the same capability, re-expressed against the `Pilot::` architecture under the MIT-only core tree.

## What Changes

- Add a `pilot_faq_suggestions` table: a reviewable FAQ candidate owned by an assistant and account, carrying question, answer, language, a source count (how many conversations produced it), a lifecycle status (`open` → `approved` / `dismissed`), and a pgvector embedding for similarity matching.
- Add a `pilot_faq_observations` table: one row per (conversation, candidate) sighting, storing the generated question/answer as produced for that conversation, and either attached to a suggestion or marked discarded (matched existing knowledge or a dismissed suggestion).
- Rework `Pilot::Conversations::FaqMiningJob`'s persistence path: instead of writing `Pilot::AssistantResponse` rows directly, each mined candidate is routed —
  - matches an approved knowledge entry → record a discarded observation (no queue noise);
  - matches a previously dismissed suggestion → record a discarded observation (dismissals stick);
  - matches an open suggestion in the same language → attach an observation and increment its source count;
  - no match → create a new open suggestion.
- Similarity matching is two-stage: an embedding shortlist (cosine distance threshold) narrows candidates, then an LLM equivalence judgment decides whether the near match is truly the same FAQ.
- Add a review API under the Pilot account namespace: paginated, searchable list filtered by assistant and status; a detail view exposing the suggestion's source conversations; edit of question/answer while open; approve (optionally with final edits) and dismiss actions.
- Approval is atomic and terminal: it creates an approved `Pilot::AssistantResponse` from the suggestion's (possibly edited) question/answer and marks the suggestion approved in the same locked operation.
- Visibility scoping: administrators see all of an account's suggestions; non-admin agents see only suggestions observed in conversations they are permitted to access.
- Add a review UI in the Pilot FAQs area: a banner/entry point showing the open-suggestion count, a suggestions list page with search and pagination, and a review dialog with editable question/answer, the list of source conversations (deep-linkable), and approve/dismiss actions.

## Capabilities

### New Capabilities
- `pilot-faq-suggestion-mining`: Resolve-time FAQ candidates are staged as deduplicated, source-counted suggestions with per-conversation observations, instead of being written straight into the knowledge base.
- `pilot-faq-suggestion-review`: Review API and interface for FAQ suggestions — list, search, inspect sources, edit, approve (converting to an approved knowledge entry), and dismiss (suppressing future re-mining of the same FAQ).

### Modified Capabilities
None.

## Impact

- New tables `pilot_faq_suggestions` and `pilot_faq_observations` (migration, pgvector index on suggestion embeddings).
- `Pilot::Conversations::FaqMiningJob` and `Custom::Pilot::FaqMiningDeduper` (persistence path replaced by suggestion routing).
- New `Pilot::FaqSuggestion` / `Pilot::FaqObservation` models, approval service, permission-aware finder, review controller and jbuilder views under `app/controllers/api/v1/accounts/pilot/`.
- New policy `Pilot::FaqSuggestionPolicy`; route additions under the Pilot namespace.
- Pilot FAQ frontend: new suggestions page, review dialog, store module, API client, and an entry point with open count on the existing FAQs page (`app/javascript/dashboard/components-next/pilot/faqs/`).
- English frontend i18n only for new labels and copy.
- LLM usage: one additional lightweight equivalence-judgment call per near-duplicate candidate; suggestion embeddings via the existing `Pilot::UpdateEmbeddingJob` pattern.
