# Pilot Port — Roadmap Status

_Last updated: 2026-05-24 (verified against code by three independent agents: Claude Explore, DeepSeek V4 Pro, Codex; closeout sweep verified by Codex sub-agents)_

High-level status of the Captain → Pilot port. One row per scoped feature, not per requirement. Granular implementation details (citation toggles, eviction atomicity, etc.) live inside the specs in `openspec/changes/pilot-full/`.

## Captain features scoped for porting to Pilot

| Feature | Status | What's missing |
|---|---|---|
| 01. Autopilot (customer-facing chatbot) | ✅ DONE | — (core inference / retrieval / handover all functional) |
| 02. Copilot (agent-side AI helper) | ✅ DONE | Drawer mounted; empty-state CTA repointed from missing `pilot_assistants_create_index` to `pilot_settings` (the canonical assistant-management surface with a Create button). |
| 03. FAQ knowledge base | ✅ DONE | — |
| 04. Document ingestion (PDF + URL + Firecrawl) | ✅ DONE | — |
| 05. Scenarios (admin playbooks) | ✅ DONE | — (scenarios CRUD works; runtime tool resolution bug counted under row 06) |
| 06. Custom tools | ✅ DONE | Backend API (V2 controller + Pundit policy + executor + SSRF guard + Liquid render). UI page `PilotToolsPage.vue` mounted at `/pilot/tools`. Vuex namespace normalized to `pilot/customTools`. Autopilot runtime registration shipped via `lib/pilot/tools/agent_tool_adapter.rb` (wraps `Pilot::CustomTool` rows for the ai-agents SDK). Scenario `tools` JSONB resolution shipped via `lib/pilot/tools/scenario_resolver.rb` with `pilot.scenario.tool_unresolved` telemetry for missing identifiers. Account-level enabled-only gating in v1; per-assistant filtering is filed as polish (no `enabled_tool_slugs` data backing on `Pilot::Assistant` yet). |
| 07. Briefing / reply suggestion | ✅ DONE | — |
| 08. Conversation utilities (Summary / Rewrite / Follow-up / Label suggestion / CSAT) | ✅ DONE | All five utilities wired and functional via `PilotActionsMenu.vue` (Summarize, Rewrite, Follow-up) + `ConversationAction.vue` (label-suggestion chips) + `CsatResponses.vue` (sentiment + themes cards). Follow-up button mounted with the standard Pilot preview / Accept-Dismiss flow. |
| 09. Autopilot admin surface (manage assistants / documents / scenarios / tools) | ✅ DONE | Verified in `routes/dashboard/pilot/routes.js`: FAQs → `PilotFaqsPage`, Documents → `PilotDocumentsPage`, Scenarios → `ScenarioBuilder`, Playground → `PlaygroundPanel`, Inboxes → `PilotInboxesPage`, Settings → `AutopilotIndex`, Copilot → `PilotCopilotEntry`. The one outlier — `pilot_tools` → `PilotPlaceholder` — is tracked separately under row 06. |
| 10. Handover (bot → human) | ✅ DONE | — |
| 11. Telemetry / event dispatch | ✅ DONE | Dispatcher, event store, payload redaction, ActionCable broadcast, 30-day retention job all in place. |
| 12. Auto-resolve | ✅ DONE via host | Host's `Conversations::ResolutionJob` (time-based) does the job. No Pilot-specific layer needed. |

## Remaining feature-level gaps (the punch list)

**Zero remaining feature-level gaps as of 2026-05-23.** All twelve scoped Captain features are at parity. Remaining work is polish (see backlog below).


## Deliberate Pilot-original additions (KEEP)

These are features Pilot ships that Captain does not. All are intentional and remain in scope:

- **Multi-provider LLM routing** — **First-class providers in `lib/llm/provider_registry.rb`**: OpenAI, Nebius, Scaleway, OpenRouter. **OpenAI-compatible endpoints** can be env-declared via the `PILOT_LLM_<SLUG>_API_KEY` mechanism (`lib/llm/config.rb:83`) — this covers any provider that exposes an OpenAI-compatible API (commonly used to point at Gemini, Mistral, Anthropic, or Ollama proxies). Native non-OpenAI-compatible adapters for those providers are NOT in the registry. Per-slot model selection via Super Admin → LLM Settings. The EU-residency play.
- **Embedding dimension control + namespace isolation + presets** — operator-controlled embedding model selection.
- **Sensitive payload redaction** — telemetry events strip raw prompts / customer messages / auth headers, replaced with length + sha256 fingerprints. GDPR safety.
- **Copilot validator tolerance + ai-agents SDK tool execution** — fixes Captain crashes when LLMs return unexpected JSON keys or emit tool calls that need executing.
- **Provider connection-test functionality + env-pre-configured detection** — fold into Super Admin LLM Settings; necessary because providers are configurable in Pilot but not in Captain.
- **Logbook (contact memory)** — experimental Konversio-original feature by Matt. **Verified shipped**: `pilot_logbook_entries` table, `Pilot::LogbookExtractionJob`, `Custom::Pilot::LogbookExtractionService`, contact-panel viewer tab, and Copilot prompt injection (functional). **Cross-feature injection beyond Copilot is incomplete** (Briefing is a logging placeholder, Autopilot has none) — completing it is tracked in the polish backlog rather than overstated here.
- **Pilot event infrastructure** — `Custom::Pilot::EventDispatcher` persists to `pilot_events`, streams via `PilotEventsChannel`, redacts sensitive fields via `PayloadRedactor`, retains for 30 days via `Pilot::EventsRetentionJob`. This is the **backend plumbing only**. An operator-facing Activity dashboard UI was not located in the 2026-05-23 audit — that question (verify-or-build) is tracked as a polish item rather than implied here.

## Deliberate execution improvements over Captain

These are NOT new features — the feature itself is at parity with Captain — but the implementation is deliberately smarter than the source product. Each is treated as covered on the roadmap; future audits should not flag them as divergences.

- **Custom Tools navigation placement** — mounted as a top-level Pilot sidebar sub-item at `/pilot/tools` instead of being nested inside an assistant workspace as Captain does. Tools data is account-scoped; the top-level placement honestly reflects this. The source product's nested layout is misleading. See `pilot-tools/spec.md` "Decision: Top-level mount instead of nesting under an assistant" for the full rationale.

Add to this list when future work makes a similar deliberate-improved-execution call so it doesn't get re-litigated.

## Cuts applied (Pilot-invented features removed)

Last cuts applied: 2026-05-23. These were built during the autonomous session
but lack Captain prior art and lack deliberate justification — removed to keep
Pilot honest to "we ship what Captain ships":

- **Onboarding wizard** (entire pilot-onboarding capability) — REMOVED 2026-05-23. Vue components, controller, routes, `pilot_onboarding_state` JSONB, `OnboardingState`, `WebsiteWidgetSeeder`, `WidgetTaglineService`, i18n all deleted. The provider connection-test + env-detection plumbing is preserved (folds into Super Admin → LLM Settings).
- **AI auto-resolve evaluator** (Pilot's half of pilot-autoresolve) — REMOVED 2026-05-23. `Custom::Pilot::AutoResolveEvaluator`, mode toggle, business-hours toggle, `/pilot/settings` panel, `pilot_autoresolve_config` JSONB, Pilot `AutoResolve*Job` family deleted. `AccountPilotAutoResolve` concern reverted to baseline (still keys off `pilot_tasks` feature — that's host code, not Pilot-original). Host's time-based auto-resolve stays unchanged. `BusinessHoursCalculator` preserved because `EventDispatcher` uses it for `pilot.autopilot.handover.triggered` reporting rows.

## Other open polish (filed, not started)

Smaller items filed during the autonomous session. Independent of the feature-level gaps above.

- Vite-plugin-ruby ESM build fix (pre-existing main breakage, blocks `assets:precompile`)
- Regenerate `db/schema.rb` after the feature-flag consolidation migrations. The schema is at version `2026_05_22_120100`, but `db/migrate/20260520170000_drop_legacy_feature_flag_columns.rb` is present and `db/schema.rb` still lists the 12 legacy `accounts.pilot_*_enabled` booleans plus `index_accounts_on_pilot_enabled`, so the checked-in schema is stale.
- Three order-dependent specs + leftover-row residue (test isolation)
- Surface LLM `prompt_tokens` / `completion_tokens` to trace spans
- Per-source Redis mutex in `Pilot::Documents::CrawlJob` (concurrency hardening)
- Resolve → FAQ-mined integration test (coverage gap)
- Drop dead `pilot_autoresolve_enabled` boolean on `accounts` (added by earlier migration, now unused)
- Drop broken `evaluated` mode from `AccountPilotAutoResolve` concern — the evaluator it pointed to was deleted in the 2026-05-23 cuts, but `pilot_auto_resolve_mode` still defaults to `evaluated` whenever `pilot_tasks` is enabled, and `pilot_tasks` is enabled by default in `config/features.yml`. Pair this cleanup with the boolean-column drop above.
- Finish Logbook prompt injection beyond Copilot: Briefing currently logs the available context instead of inserting it into the prompt, and Autopilot does not reference Logbook context.
- Confirm or build a Pilot Activity dashboard UI; current evidence only proves the event store, ActionCable stream, and retention job.
- Per-assistant tool enablement column on `Pilot::Assistant` — pilot-tools spec calls for assistant-scoped filtering of the account-wide tool set, but `Pilot::Assistant` has no `enabled_tool_slugs` column. Custom Tools wiring shipped account-level enabled-only gating in v1; this is the polish to align with spec.
- Direct spec coverage for sibling listener-enqueued Pilot jobs — `Pilot::LabelSuggestionJob` and `Pilot::Conversations::FaqMiningJob` lack the same handover / failure-swallow / typing-bookend direct coverage that just landed for `Pilot::AutopilotInferenceJob`. Both are listener-enqueued like AutopilotInferenceJob; both currently rely on indirect service-level specs. (`Pilot::CopilotInferenceJob` already has direct coverage.)

## Verification audit log

- **2026-05-23**: triangulated review by Claude Explore + DeepSeek V4 Pro + Codex against the status claim "1:1 Core Feature Parity, all DONE". All three agents independently confirmed: `routes.js:55` mounts `PilotPlaceholder` at `/pilot/tools` (real `PilotToolsPage.vue` orphaned); `autopilot_service.rb:164` registers only `SearchDocumentation` and `autopilot_service.rb:179` builds scenarios with `tools: []` (custom tools never enter runtime); `FollowUpSuggestionsButton.vue` has no import outside itself. Provider list overstated (4 first-class, rest are OpenAI-compatible env-declared, not native). Row 09 re-audited and confirmed mostly DONE — only the tools route is placeholder (tracked under row 06). DeepSeek nit: the `evaluated` mode in `AccountPilotAutoResolve` concern is now dead since the evaluator was deleted in the cuts; added to polish backlog.
- **2026-05-23 follow-up Codex audit**: found additional precision issues after the shared-agent convergence: custom tools page has Vuex namespace drift (`pilot/customTools` vs `pilotCustomTools`), Logbook context injection is only real in Copilot, and Pilot Activity dashboard UI is unverified despite solid telemetry/event infrastructure.
- **2026-05-23 DeepSeek follow-up verified by Codex**: confirmed three additional roadmap omissions: checked-in `db/schema.rb` is stale after the legacy feature-flag drop migration; Copilot zero-assistant empty state links to nonexistent route `pilot_assistants_create_index`; `AccountPilotAutoResolve#pilot_auto_resolve_mode` still reaches broken `evaluated` mode when `pilot_tasks` is enabled by default. **Severity verified by Claude grep**: the `evaluated` mode is reachable but never read at runtime — no callers of `pilot_auto_resolve_evaluated?` exist anywhere. Dead code, not a crash path. Polish-backlog severity is correct.
- **2026-05-23 punch list closure**: three parallel agents landed the openspec `pilot-port-finalize` changes. Section 1 Custom tools wiring (route flip, Vuex namespace normalization, `AgentToolAdapter` for autopilot runtime registration, `ScenarioResolver` for scenario tool resolution, 6 + 3 new RSpec examples, 55 total green). Section 2 Copilot empty-state route fix (single-line route name change, no spec needed). Section 3 Follow-up button mount (wired into `PilotActionsMenu.vue` with the Pilot preview / Accept-Dismiss flow). Rows 02, 06, 08 flipped from 🟡 PARTIAL to ✅ DONE. Per-assistant tool enablement column discovered as a spec/data mismatch and filed in polish backlog rather than expanding scope.
- **2026-05-23 coverage closure**: added `spec/jobs/pilot/autopilot_inference_job_spec.rb` for the previously indirect-only `Pilot::AutopilotInferenceJob` coverage gap. The spec covers eligibility no-ops, normal reply persistence, handover side effects, swallowed service errors, and typing on/off lifecycle including the error path.
- **2026-05-24 closeout verification**: OpenSpec `pilot-port-finalize` closeout is checked through task 4.5. Full Pilot sweep passed (`599 examples, 0 failures, 4 pending`); touched Ruby RuboCop passed (`7 files inspected, no offenses`); touched JS/Vue scoped ESLint passed with 0 errors (warnings only, not auto-fixed to avoid unrelated churn). The only task-list correction was narrowing 1.8 to the implemented account-level custom-tool gating; per-assistant tool enablement remains polish.
