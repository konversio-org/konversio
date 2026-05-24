# Pilot Remaining Fix List

Status as of 2026-05-24: Captain parity is closed. These are remaining polish,
coverage, hardening, or worktree hygiene items. They are not parity blockers.

## P1: Build / Test Blockers

No active build or test blockers.

## P1: Product Polish

No active product-polish items.

## Completed During Tackle Pass

- **Resolved stale `SearchDocumentation` unavailable pending spec**
  - Replaced the stale pending example with constant hiding coverage for the unavailable branch.
  - Verified by `spec/services/custom/pilot/tools/search_documentation_spec.rb`.

- **Added cross-source FAQ dedup coverage**
  - Reused `Custom::Pilot::FaqMiningDeduper` when document mining sees existing responses from other sources, and covered duplicate suppression.
  - Verified by `spec/jobs/pilot/document_response_builder_job_spec.rb` and `spec/jobs/pilot/conversations/faq_mining_job_spec.rb`.

- **Expanded direct listener-enqueued job specs**
  - Added direct no-op, service invocation, swallowed-error, persistence, and non-destructive coverage for `Pilot::LabelSuggestionJob`.
  - Added direct service invocation and missing-conversation no-op coverage for `Pilot::Conversations::FaqMiningJob`.

- **Added Resolve to FAQ-mined integration coverage**
  - `PilotResolveListener` now has an inline job-flow spec proving resolve events create pending FAQ rows and remain idempotent for the same transcript.

- **Resolved unrelated dirty frontend files**
  - Isolated the four formatter-only Vue diffs into a separate style commit.

- **Added per-source Redis mutex to `Pilot::Documents::CrawlJob`**
  - Crawl execution now uses an assistant/source-scoped Redis lock with a bounded TTL, reschedules on contention, and releases it in `ensure`.
  - Specs cover lock contention and separate keys for different sources.

- **Surfaced LLM token usage to trace spans**
  - Autopilot and Copilot attach runner usage when present; Briefing attaches RubyLLM usage from `Pilot::ReplySuggestionService`.
  - Specs assert prompt/completion token attributes on each path.

- **Finished Logbook prompt injection beyond Copilot**
  - Briefing passes Logbook facts into `Pilot::ReplySuggestionService` as an extra system message.
  - Autopilot assistant instructions include Logbook facts when `pilot_logbook` is enabled.

- **Closed CrawlJob webhook/signature and assistant-scoping coverage**
  - Removed the stale `webhooks/firecrawl` pending from `CrawlJob` specs.
  - Expanded the real `/webhooks/pilot/bulk_crawl/:assistant_id/:token` request spec for cross-assistant tokens and spoofed payload ownership.

- **Added real `Agents::Runner` integration coverage for Autopilot**
  - Replaced the pending with a spec that keeps `Agents::Runner.with_agents` real and stubs only the RubyLLM chat boundary while invoking `search_documentation`.

- **Fixed production asset precompile package-manager detection**
  - ViteRuby now uses pnpm explicitly instead of detecting npm from the stale `package-lock.json`.
  - Verified by `env RAILS_ENV=production SECRET_KEY_BASE=dummy POSTGRES_HOST=localhost REDIS_URL=redis://localhost:6379/0 bundle exec rails assets:precompile`.

- **Verified order-dependent spec / leftover-row note is stale**
  - Pilot spec slice passed with seeds `12345` and `54321`.
  - Post-sweep test database check showed zero rows in all `pilot_*` tables.

- **Built Pilot Activity dashboard UI**
  - Added account-scoped API v2 event listing backed by `pilot_events`.
  - Mounted `/pilot/activity` in the Pilot sidebar with loading, empty, error, table, and pagination states.
  - Verified by the new events controller request spec and scoped JS/Vue lint.

- **Added per-assistant custom-tool enablement**
  - Added `Pilot::Assistant#enabled_tool_slugs` with a backfill that preserves current enabled account tools for existing assistants.
  - Wired assistant settings to select enabled account tools per assistant.
  - Filtered Autopilot and scenario tool registration through assistant-level selections.
  - Verified by focused host and container RSpec slices plus touched Ruby/Vue lint.
