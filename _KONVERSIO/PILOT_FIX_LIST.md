# Pilot Remaining Fix List

Status as of 2026-05-24: Captain parity is closed. These are remaining polish,
coverage, hardening, or worktree hygiene items. They are not parity blockers.

## P1: Build / Test Blockers

1. **Fix Vite-plugin-ruby ESM build issue**
   - Current state: pre-existing main breakage blocks `assets:precompile`.
   - Fix: reproduce with the production asset build, identify the ESM/CJS incompatibility, and update the import/config path with the smallest compatible change.
   - Verify: `bundle exec rails assets:precompile` or the repo's production asset build command passes.

2. **Clean up order-dependent specs and leftover-row residue**
   - Current state: roadmap notes three order-dependent specs plus leftover-row residue.
   - Fix: identify the failing seed/order, isolate leaked records or shared globals, and move setup/cleanup into the offending specs.
   - Verify: randomized repeat runs pass for the affected files and the Pilot sweep still passes.

## P1: Product Polish

3. **Finish Logbook prompt injection beyond Copilot**
   - Current state: Copilot injection is functional; Briefing logs available context instead of inserting it into the prompt; Autopilot has no Logbook context path.
   - Fix: inject the standard Logbook context message into Briefing and Autopilot prompts behind `pilot_logbook`.
   - Verify: specs prove prompt/context includes Logbook entries when enabled and excludes them when disabled.

4. **Confirm or build Pilot Activity dashboard UI**
   - Current state: event store, ActionCable stream, redaction, and retention job exist; operator-facing Activity UI was not verified.
   - Fix: either locate and document the existing UI route, or add a minimal Activity page backed by `pilot_events`.
   - Verify: UI route renders event rows and respects account scoping.

5. **Add per-assistant custom-tool enablement**
   - Current state: custom tools are account-scoped and gated by `Pilot::CustomTool#enabled`; `Pilot::Assistant` has no `enabled_tool_slugs`-style backing.
   - Fix: add assistant-level storage for enabled tool slugs/IDs, wire admin UI selection, and filter `AgentToolAdapter` registration.
   - Verify: Autopilot and scenario specs prove disabled-for-assistant tools are not registered even if enabled at account level.

## P2: Coverage Gaps

6. **Add real `Agents::Runner` integration spec for Autopilot**
    - Current pending spec: `spec/services/custom/pilot/autopilot_service_spec.rb:135`.
    - Current state: most Autopilot specs stub `Agents::Runner.with_agents`.
    - Fix: stub only the LLM HTTP boundary and let `Agents::Runner` execute at least one real tool call.
    - Verify: spec fails if tool registration, scenario handoff wiring, or prompt handoff sentinel instructions break.

7. **Add CrawlJob webhook/signature and assistant-scoping coverage**
    - Current pending spec: `spec/jobs/pilot/documents/crawl_job_spec.rb:257`.
    - Current state: Firecrawl/webhook signature and assistant scoping coverage are pending.
    - Fix: add request/job specs around signed callbacks and assistant-bound source selection.
    - Verify: invalid signatures are rejected, valid callbacks enqueue/process correctly, and sources cannot cross assistant/account boundaries.

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
