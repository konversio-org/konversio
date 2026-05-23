# Pilot Port — Roadmap Status

_Last updated: 2026-05-23_

High-level status of the Captain → Pilot port. One row per scoped feature, not per requirement. Granular implementation details (citation toggles, eviction atomicity, etc.) live inside the specs in `openspec/changes/pilot-full/`.

## Captain features scoped for porting to Pilot

| Feature | Status | What's missing |
|---|---|---|
| Autopilot (customer-facing chatbot) | ✅ DONE | — |
| Copilot (agent-side AI helper) | ✅ DONE | — |
| FAQ knowledge base | ✅ DONE | — |
| Document ingestion (PDF + URL + Firecrawl) | ✅ DONE | — |
| Scenarios (admin playbooks) | ✅ DONE | — |
| Custom tools | 🟡 PARTIAL | Backend incomplete (executor/guard are ready, but V1 controller is missing entirely). **Admin UI tools panel not built.** |
| Briefing / reply suggestion | ✅ DONE | — |
| Conversation utilities (Summary / Rewrite / Follow-up / Label suggestion / CSAT) | 🟡 PARTIAL | API + services done. **No composer/timeline UI affordances** — agents cannot click "Summarize" or "Rewrite" from the dashboard. |
| Autopilot admin surface (manage assistants / documents / scenarios / tools) | 🟡 PARTIAL | FAQs page (V2) ships. **Other admin pages and Pilot sidebar group not built** — operators currently cannot manage assistants/scenarios/documents/tools through the dashboard. V1 controllers exist (API works), V2 admin UI does not. |
| Handover (bot → human) | ✅ DONE | — |
| Telemetry / event dispatch | ✅ DONE | Dispatcher, event store, payload redaction, ActionCable broadcast, 30-day retention job all in place. |
| Auto-resolve | ✅ DONE via host | Host's `Conversations::ResolutionJob` (time-based) does the job. No Pilot-specific layer needed. |

## Remaining feature-level gaps (the punch list)

Three real Captain features are partially shipped — all backend, no UI:

1. **Custom tools V1 controller + admin UI** — the API endpoints and control panel that lets admins CRUD custom HTTP tools
2. **Conversation utilities UI affordances** — the composer sparkle buttons (Summarize / Rewrite / Follow-ups / Suggested labels) and CSAT report enhancements
3. **Autopilot admin pages + Pilot sidebar group** — the dashboard surface for managing assistants / documents / scenarios / tools (only FAQs page exists in V2 today)

Once these three land, every Captain feature scoped for the port is shipped.

## Deliberate Pilot-original additions (KEEP)

These are features Pilot ships that Captain does not. All are intentional and remain in scope:

- **Multi-provider LLM routing** — Scaleway / Mistral / Nebius / Groq / Ollama / OpenAI / Anthropic / Gemini, per-slot model selection via Super Admin → LLM Settings. The EU-residency play.
- **Embedding dimension control + namespace isolation + presets** — operator-controlled embedding model selection.
- **Sensitive payload redaction** — telemetry events strip raw prompts / customer messages / auth headers, replaced with length + sha256 fingerprints. GDPR safety.
- **Copilot validator tolerance + ai-agents SDK tool execution** — fixes Captain crashes when LLMs return unexpected JSON keys or emit tool calls that need executing.
- **Provider connection-test functionality + env-pre-configured detection** — fold into Super Admin LLM Settings; necessary because providers are configurable in Pilot but not in Captain.
- **Logbook (contact memory)** — experimental Konversio-original feature by Matt. Built on its own infrastructure (`pilot_logbook_entries` table, `Pilot::LogbookExtractionJob`, dedicated viewer tab, cross-feature injection into Briefing/Copilot/Autopilot prompts).
- **Pilot Activity view (telemetry dashboard)** — operator-debugging audit trail. Necessary for viewing emitted events, tracking tool execution results, and troubleshooting prompt/LLM issues.

## Cuts agreed (Pilot-invented features being removed)

These were built during the autonomous session but lack Captain prior art and lack deliberate justification — being removed to keep Pilot honest to "we ship what Captain ships":

- **Onboarding wizard** (entire pilot-onboarding capability) — Vue components, controller, routes, `pilot_onboarding_state` JSONB, `OnboardingState`, `WebsiteWidgetSeeder`, `WidgetTaglineService`, i18n. The provider connection-test + env-detection plumbing is preserved and folded into Super Admin → LLM Settings.
- **AI auto-resolve evaluator** (Pilot's half of pilot-autoresolve) — `Custom::Pilot::AutoResolveEvaluator`, mode toggle, business-hours toggle, `/pilot/settings` panel, `pilot_autoresolve_config` JSONB, the Pilot `AutoResolveJob` / `AutoResolveConversationJob`. Host's time-based auto-resolve stays unchanged.

## Other open polish (filed, not started)

Smaller items filed during the autonomous session. Independent of the feature-level cuts above.

- Onboarding wire-up follow-ups (moot once wizard is cut)
- Business-hours-aware idle calc (moot once Pilot auto-resolve is cut)
- Vite-plugin-ruby ESM build fix (pre-existing main breakage, blocks `assets:precompile`)
- Three order-dependent specs + leftover-row residue (test isolation)
- Surface LLM `prompt_tokens` / `completion_tokens` to trace spans
- Per-source Redis mutex in `Pilot::Documents::CrawlJob` (concurrency hardening)
- Resolve → FAQ-mined integration test (coverage gap)
