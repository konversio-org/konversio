# Pilot Remaining Fix List

Status as of 2026-05-24: Captain parity is closed. These are remaining polish,
coverage, hardening, or worktree hygiene items. They are not parity blockers.

## P0: Worktree Hygiene

1. **Resolve unrelated dirty frontend files**
   - Files: `ContactsForm.vue`, `WootWriter/Editor.vue`, `AutomationRuleForm.vue`, `app/javascript/v3/App.vue`.
   - Current state: dirty before the Pilot cleanup commits; not touched by the Pilot closeout.
   - Fix: inspect owner intent, then either commit separately, finish the related frontend work, or explicitly revert with approval.
   - Verify: `git status --short` has no unrelated dirty files.

## P1: Build / Test Blockers

2. **Fix Vite-plugin-ruby ESM build issue**
   - Current state: pre-existing main breakage blocks `assets:precompile`.
   - Fix: reproduce with the production asset build, identify the ESM/CJS incompatibility, and update the import/config path with the smallest compatible change.
   - Verify: `bundle exec rails assets:precompile` or the repo's production asset build command passes.

3. **Clean up order-dependent specs and leftover-row residue**
   - Current state: roadmap notes three order-dependent specs plus leftover-row residue.
   - Fix: identify the failing seed/order, isolate leaked records or shared globals, and move setup/cleanup into the offending specs.
   - Verify: randomized repeat runs pass for the affected files and the Pilot sweep still passes.

## P1: Pilot Runtime Hardening

4. **Add per-source Redis mutex to `Pilot::Documents::CrawlJob`**
   - Current state: crawl jobs can overlap for the same source.
   - Fix: add a source-scoped Redis lock around crawl execution; keep the lock timeout bounded and release in `ensure`.
   - Verify: job spec proves two jobs for the same source do not run concurrently and jobs for different sources can proceed.

5. **Surface LLM token usage to trace spans**
   - Current state: `TraceSpan` supports token attributes, but usage is not consistently pushed from Pilot LLM call sites.
   - Fix: propagate `prompt_tokens` / `completion_tokens` from runner/service results where available.
   - Verify: specs assert token attributes on trace spans for Autopilot, Copilot, and utility service paths that expose usage.

## P1: Product Polish

6. **Finish Logbook prompt injection beyond Copilot**
   - Current state: Copilot injection is functional; Briefing logs available context instead of inserting it into the prompt; Autopilot has no Logbook context path.
   - Fix: inject the standard Logbook context message into Briefing and Autopilot prompts behind `pilot_logbook`.
   - Verify: specs prove prompt/context includes Logbook entries when enabled and excludes them when disabled.

7. **Confirm or build Pilot Activity dashboard UI**
   - Current state: event store, ActionCable stream, redaction, and retention job exist; operator-facing Activity UI was not verified.
   - Fix: either locate and document the existing UI route, or add a minimal Activity page backed by `pilot_events`.
   - Verify: UI route renders event rows and respects account scoping.

8. **Add per-assistant custom-tool enablement**
   - Current state: custom tools are account-scoped and gated by `Pilot::CustomTool#enabled`; `Pilot::Assistant` has no `enabled_tool_slugs`-style backing.
   - Fix: add assistant-level storage for enabled tool slugs/IDs, wire admin UI selection, and filter `AgentToolAdapter` registration.
   - Verify: Autopilot and scenario specs prove disabled-for-assistant tools are not registered even if enabled at account level.

## P2: Coverage Gaps

9. **Add real `Agents::Runner` integration spec for Autopilot**
    - Current pending spec: `spec/services/custom/pilot/autopilot_service_spec.rb:135`.
    - Current state: most Autopilot specs stub `Agents::Runner.with_agents`.
    - Fix: stub only the LLM HTTP boundary and let `Agents::Runner` execute at least one real tool call.
    - Verify: spec fails if tool registration, scenario handoff wiring, or prompt handoff sentinel instructions break.

10. **Add CrawlJob webhook/signature and assistant-scoping coverage**
    - Current pending spec: `spec/jobs/pilot/documents/crawl_job_spec.rb:257`.
    - Current state: Firecrawl/webhook signature and assistant scoping coverage are pending.
    - Fix: add request/job specs around signed callbacks and assistant-bound source selection.
    - Verify: invalid signatures are rejected, valid callbacks enqueue/process correctly, and sources cannot cross assistant/account boundaries.

11. **Add Resolve to FAQ-mined integration spec**
    - Current state: roadmap lists Resolve -> FAQ-mined as an integration coverage gap.
    - Fix: exercise the resolution listener/job path through FAQ mining and pending `AssistantResponse` creation.
    - Verify: resolving a qualifying conversation creates expected pending FAQ rows and avoids duplicates.

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
