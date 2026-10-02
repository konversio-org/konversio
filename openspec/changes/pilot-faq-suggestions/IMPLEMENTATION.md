# Implementation Report: pilot-faq-suggestions

Date: 2026-10-02. Branch: `feat/pilot-faq-suggestions` (worktree `tmp/wt-faq`).

## What was implemented, per spec section

### pilot-faq-suggestion-mining

- **FAQ suggestion records** — `Pilot::FaqSuggestion` (`app/models/pilot/faq_suggestion.rb`): assistant/account
  ownership (account derived from assistant), question/answer, normalized language, `source_count`, lifecycle enum
  `open/approved/dismissed` (default `open`), pgvector(1536) embedding of `"<question>: <answer>"` refreshed
  asynchronously via the new `Pilot::UpdateFaqSuggestionEmbeddingJob` on create/update **while open** when
  question/answer changed (or the embedding is missing). Scopes: `ordered` (source_count desc, updated_at desc),
  `by_language`. Language helpers: `normalize_language` (hyphen/underscore variants collapsed to primary subtag,
  lowercased) and `language_for(conversation)` (account locale, default-locale fallback).
- **Per-conversation observations** — `Pilot::FaqObservation` (`app/models/pilot/faq_observation.rb`): account
  (derived from conversation), conversation, optional suggestion, generated question/answer, language, enum
  `attached/discarded`. Attached requires a same-account suggestion (validation). One attached observation per
  (conversation, suggestion) enforced by a partial unique index.
- **Two-stage candidate matching** — `Custom::Pilot::FaqSuggestionMatcher`
  (`custom/app/services/custom/pilot/faq_suggestion_matcher.rb`): embeds `"<question>: <answer>"`, shortlists up to
  5 nearest neighbors under cosine distance 0.3 per pool inside a transaction with `SET LOCAL enable_indexscan = off`
  (so status/language filters cannot make the approximate index miss matches), then runs a boolean LLM equivalence
  judgment per shortlisted record. Pool order: approved knowledge → dismissed suggestions (same language) → open
  suggestions (same language). Routes: `:knowledge` / `:dismissed` (discard), `:attach`, `:create`; plus `:duplicate`
  for in-batch near-duplicates (the fresh suggestion has no embedding yet, preserving the old deduper's in-batch
  behavior). Judgment failures (LLM error, unparseable/non-boolean verdict) raise `JudgmentError`.
- **Mining persistence rework** — `Pilot::Conversations::FaqMiningJob` (`app/jobs/pilot/conversations/faq_mining_job.rb`):
  `persist_survivors`/`create_response` replaced by candidate routing. Approved-knowledge or dismissed match →
  discarded observation. Open match → attach under a row lock with re-verification (still open + question/answer
  unchanged since match); a failed re-verification re-routes the candidate (max 3 attempts). Same conversation
  re-attach is a no-op (no double count). No match → open suggestion with source_count 1 + attached observation.
  Transcript build, human-reply short-circuit, digest idempotency, and error swallowing kept; the digest is only
  recorded on success, so a raised judgment failure leaves the conversation re-mineable.
- **Generation-quality gates** — audited `Custom::Pilot::FaqMiningService`'s prompt. It already required
  transcript-only facts, agent/customer tagging, automated-reply exclusion, self-contained pairs, and an empty
  result; gaps closed (original wording): answers built ONLY from human-agent statements; durable/publicly reusable
  knowledge only (no customer/order/one-off specifics); no private identifiers in output.
- **`Custom::Pilot::FaqMiningDeduper` removed** — its only caller was the mining job; corpus dedup is absorbed by
  the matcher's pools, in-batch dedup by the matcher's per-run vector memory. Listener spec and
  `docs/faq-generation-prompting.md` updated.

### pilot-faq-suggestion-review

- **Review API** — `Api::V1::Accounts::Pilot::FaqSuggestionsController`
  (`app/controllers/api/v1/accounts/pilot/faq_suggestions_controller.rb`) behind the existing `pilot` +
  `pilot_autopilot` feature flags:
  - `index`: paginated 25/page, filters `assistant_id`, `status`, ILIKE `search` over question/answer; meta carries
    `current_page`, `per_page`, `total_count`, `total_pages`.
  - `show`: suggestion fields + up to 50 most recent observations, each with conversation `id`/`display_id`,
    permission-filtered per requesting user.
  - `update`: question/answer, open-only under a row lock (non-open → 404), blank values → 422.
  - `approve`: via `Pilot::FaqSuggestionApprovalService` — row lock, non-open raises `ActiveRecord::RecordNotFound`
    (idempotent-retry safe), optional final edits, creates the approved `Pilot::AssistantResponse` (rendered as the
    response payload) and marks the suggestion approved atomically.
  - `dismiss`: open-only under a row lock.
- **Permission scoping** — `Pilot::FaqSuggestionFinder` (`app/finders/pilot/faq_suggestion_finder.rb`): admins get all
  account suggestions; agents only suggestions with an observation on a conversation returned by
  `Conversations::PermissionFilterService`. `show` observation preview applies the same filter. `load_suggestion`
  goes through the finder, so inaccessible records behave as not-found. `Pilot::FaqSuggestionPolicy` permits
  index/show/update/approve/dismiss for any account member (data scoping lives in the finder).
- **Routes** — `resources :faq_suggestions, only: [:index, :show, :update]` + member `post :approve`, `post :dismiss`
  under the v1 Pilot account namespace (`config/routes.rb`).
- **Review UI** (`app/javascript/dashboard/components-next/pilot/faqs/suggestions/`):
  - `PilotFaqSuggestionsPage.vue`: assistant picker, debounced search, pagination, per-card
    question/answer/source-count, quick approve/dismiss, review-dialog launcher; URL query kept in sync; after a
    removal on a now-empty page the page steps back one page and refetches. Route `pilot_faq_suggestions` at
    `accounts/:accountId/pilot/faqs/suggestions`.
  - `SuggestionReviewDialog.vue`: editable question/answer (required, trimmed), source-conversation list loaded from
    `show` (each row deep-links to `inbox_conversation`), save / approve (with edits) / dismiss actions, alerts via
    i18n.
  - Entry point on `PilotFaqsPage.vue`: banner with the open-suggestion count, refetched whenever the selected
    assistant changes, navigating to the suggestions page.
  - API client `app/javascript/dashboard/api/pilot/faqSuggestions.js` (account-scoped v1); store module
    `app/javascript/dashboard/store/pilot/faqSuggestions/` with `fetchOpenCount` stale-request guard (monotonic
    token) and local removal on approve/dismiss.
  - English-only i18n under `PILOT.FAQ_SUGGESTIONS` in `en/pilot.json`.

## Files added / changed

Added (backend): migration `db/migrate/20261002120000_create_pilot_faq_suggestions_and_observations.rb`;
`app/models/pilot/faq_suggestion.rb`, `app/models/pilot/faq_observation.rb`;
`app/jobs/pilot/update_faq_suggestion_embedding_job.rb`;
`custom/app/services/custom/pilot/faq_suggestion_matcher.rb`;
`app/services/pilot/faq_suggestion_approval_service.rb`; `app/finders/pilot/faq_suggestion_finder.rb`;
`app/policies/pilot/faq_suggestion_policy.rb`;
`app/controllers/api/v1/accounts/pilot/faq_suggestions_controller.rb`;
4 jbuilder views under `app/views/api/v1/accounts/pilot/faq_suggestions/`;
factories `spec/factories/pilot_faq_suggestions.rb`, `spec/factories/pilot_faq_observations.rb`.

Changed (backend): `app/jobs/pilot/conversations/faq_mining_job.rb` (routing), `app/models/pilot/assistant.rb`
(+`has_many :faq_suggestions`), `app/models/account.rb` (+2 associations),
`custom/app/services/custom/pilot/faq_mining_service.rb` (prompt gates), `config/routes.rb`,
`db/schema.rb` (post-migrate), `.rubocop_todo.yml` (mirrors the existing `update_embedding_job.rb`
`update_column` exclusion), `docs/faq-generation-prompting.md` (stale deduper reference).

Removed: `custom/app/services/custom/pilot/faq_mining_deduper.rb`.

Added (frontend): `app/javascript/dashboard/api/pilot/faqSuggestions.js`;
`app/javascript/dashboard/store/pilot/faqSuggestions/index.js` + `specs/faqSuggestions.spec.js`;
`components-next/pilot/faqs/suggestions/{PilotFaqSuggestionsPage,SuggestionCard,SuggestionReviewDialog}.vue` +
2 spec files. Changed: `store/index.js` (module registration), `routes/dashboard/pilot/routes.js` (new route),
`components-next/pilot/faqs/PilotFaqsPage.vue` (banner + count fetch), `i18n/locale/en/pilot.json`.

## Migrations

`20261002120000_create_pilot_faq_suggestions_and_observations` (unique timestamp; additive). Applied with
`RAILS_ENV=test bundle exec rails db:migrate`; specs re-run; `db/schema.rb` committed. Indexes: composite review-queue
`(account_id, assistant_id, status, language)`, ivfflat `vector_cosine_ops` on suggestion embeddings, partial unique
`(conversation_id, faq_suggestion_id) WHERE faq_suggestion_id IS NOT NULL` on observations.

## Test commands + results

- `RAILS_ENV=test bundle exec rspec spec/models/pilot spec/jobs/pilot/conversations/faq_mining_job_spec.rb
  spec/services/pilot/faq_suggestion_approval_service_spec.rb spec/services/custom/pilot/faq_suggestion_matcher_spec.rb
  spec/services/custom/pilot/faq_mining_service_spec.rb spec/controllers/api/v1/accounts/pilot/
  spec/listeners/pilot_resolve_listener_spec.rb` — all green (103 controller-request examples; 117 across
  models+job; 8 matcher + 5 approval + 8 mining-service examples; 8 listener examples; 0 failures total).
- `bundle exec rubocop -a` on all touched Ruby files — 0 offenses remaining.
- `pnpm eslint` on all touched JS/Vue files — 0 errors (418 pre-existing repo warnings).
- `pnpm test` (full vitest) — 399 files / 3867 tests passed.

Every §Validation scenario in both spec docs is covered by a green automated spec except the end-to-end manual smoke
(tasks.md #23) — see deferrals.

## Deviations from spec

- **Suggestion embedding job**: proposal text mentions the "`Pilot::UpdateEmbeddingJob` pattern"; implemented as a
  dedicated `Pilot::UpdateFaqSuggestionEmbeddingJob` (same shape, embeds the suggestion's `"<question>: <answer>"`
  matching text) instead of overloading the response-specific job.
- **Embedding failure during matching**: treated as "unmatched → create" with an error log (the new suggestion still
  gets an async embedding refresh, self-healing once the provider recovers). Only LLM *judgment* failures raise, per
  spec.
- **In-batch dedup**: kept (from the removed deduper) inside the matcher as a per-run vector memory, so two identical
  candidates from one conversation still persist once; the second routes to `:duplicate` without an observation.
- **Frontend page composition**: header built locally (back button + `AssistantPicker` + search) rather than reusing
  `PilotFaqsHeader`, whose title/create button are coupled to the FAQs list.

## Blockers / deferrals

- **tasks.md #23 (manual smoke test)**: requires a live environment with LLM + embedding credentials; not executed
  here. The identical chain is covered end-to-end by automated specs: resolve → suggestion+observation
  (listener/job specs), repeat sighting → source_count increment, dismiss → discarded observation on re-mining,
  approve-with-edit → approved knowledge entry (job/matcher/service/request specs). Left unticked intentionally.
