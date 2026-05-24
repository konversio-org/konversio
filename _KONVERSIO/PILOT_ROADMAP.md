# Pilot Port — Roadmap Status

_Last updated: 2026-05-23_

High-level status of the Captain → Pilot port. One row per scoped feature, not per requirement. Granular implementation details (citation toggles, eviction atomicity, etc.) live inside the specs in `openspec/changes/pilot-full/`.

## Captain features scoped for porting to Pilot

| Feature | Status | What's missing |
|---|---|---|
| 01. Autopilot (customer-facing chatbot) | ✅ DONE | — |
| 02. Copilot (agent-side AI helper) | ✅ DONE | — |
| 03. FAQ knowledge base | ✅ DONE | — |
| 04. Document ingestion (PDF + URL + Firecrawl) | ✅ DONE | — |
| 05. Scenarios (admin playbooks) | ✅ DONE | — |
| 06. Custom tools | ✅ DONE | — |
| 07. Briefing / reply suggestion | ✅ DONE | — |
| 08. Conversation utilities (Summary / Rewrite / Follow-up / Label suggestion / CSAT) | ✅ DONE | — |
| 09. Autopilot admin surface (manage assistants / documents / scenarios / tools) | ✅ DONE | — |
| 10. Handover (bot → human) | ✅ DONE | — |
| 11. Telemetry / event dispatch | ✅ DONE | Dispatcher, event store, payload redaction, ActionCable broadcast, 30-day retention job all in place. |
| 12. Auto-resolve | ✅ DONE via host | Host's `Conversations::ResolutionJob` (time-based) does the job. No Pilot-specific layer needed. |

## Remaining feature-level gaps (the punch list)

All Captain features scoped for the port are fully shipped. There are no remaining gaps.

## Deliberate Pilot-original additions (KEEP)

These are features Pilot ships that Captain does not. All are intentional and remain in scope:

- **Multi-provider LLM routing** — Scaleway / Mistral / Nebius / Groq / Ollama / OpenAI / Anthropic / Gemini, per-slot model selection via Super Admin → LLM Settings. The EU-residency play.
- **Embedding dimension control + namespace isolation + presets** — operator-controlled embedding model selection.
- **Sensitive payload redaction** — telemetry events strip raw prompts / customer messages / auth headers, replaced with length + sha256 fingerprints. GDPR safety.
- **Copilot validator tolerance + ai-agents SDK tool execution** — fixes Captain crashes when LLMs return unexpected JSON keys or emit tool calls that need executing.
- **Provider connection-test functionality + env-pre-configured detection** — fold into Super Admin LLM Settings; necessary because providers are configurable in Pilot but not in Captain.
- **Logbook (contact memory)** — experimental Konversio-original feature by Matt. Built on its own infrastructure (`pilot_logbook_entries` table, `Pilot::LogbookExtractionJob`, dedicated viewer tab, cross-feature injection into Briefing/Copilot/Autopilot prompts).
- **Pilot Activity view (telemetry dashboard)** — operator-debugging audit trail. Necessary for viewing emitted events, tracking tool execution results, and troubleshooting prompt/LLM issues.

## Deliberate execution improvements over Captain

These are NOT new features — the feature itself is at parity with Captain — but the implementation is deliberately smarter than the source product. Each is treated as covered on the roadmap; future audits should not flag them as divergences.

- **Custom Tools navigation placement** — mounted as a top-level Pilot sidebar sub-item at `/pilot/tools` instead of being nested inside an assistant workspace as Captain does. Tools data is account-scoped; the top-level placement honestly reflects this. The source product's nested layout is misleading. See `pilot-tools/spec.md` "Decision: Top-level mount instead of nesting under an assistant" for the full rationale.

Add to this list when future work makes a similar deliberate-improved-execution call so it doesn't get re-litigated.

## Cuts applied (Pilot-invented features removed)

Last cuts applied: 2026-05-23. These were built during the autonomous session
but lack Captain prior art and lack deliberate justification — removed to keep
Pilot honest to "we ship what Captain ships":

- **Onboarding wizard** (entire pilot-onboarding capability) — REMOVED 2026-05-23. Vue components, controller, routes, `pilot_onboarding_state` JSONB, `OnboardingState`, `WebsiteWidgetSeeder`, `WidgetTaglineService`, i18n all deleted. The provider connection-test + env-detection plumbing is preserved (folds into Super Admin → LLM Settings).
- **AI auto-resolve evaluator** (Pilot's half of pilot-autoresolve) — REMOVED 2026-05-23. `Custom::Pilot::AutoResolveEvaluator`, mode toggle, business-hours toggle, `/pilot/settings` panel, `pilot_autoresolve_config` JSONB, Pilot `AutoResolve*Job` family deleted. `AccountPilotAutoResolve` concern reverted to baseline (still keys off `pilot_tasks` feature). Host's time-based auto-resolve stays unchanged. `BusinessHoursCalculator` preserved because `EventDispatcher` uses it for `pilot.autopilot.handover.triggered` reporting rows.

## Other open polish (filed, not started)

Smaller items filed during the autonomous session. Independent of the feature-level cuts above.

- Onboarding wire-up follow-ups (moot once wizard is cut)
- Business-hours-aware idle calc (moot once Pilot auto-resolve is cut)
- Vite-plugin-ruby ESM build fix (pre-existing main breakage, blocks `assets:precompile`)
- Three order-dependent specs + leftover-row residue (test isolation)
- Surface LLM `prompt_tokens` / `completion_tokens` to trace spans
- Per-source Redis mutex in `Pilot::Documents::CrawlJob` (concurrency hardening)
- Resolve → FAQ-mined integration test (coverage gap)
