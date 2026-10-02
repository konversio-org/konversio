# Implementation: pilot-response-integrity

Branch: `feat/pilot-response-integrity` (worktree `tmp/wt-integrity`). Implemented entirely from
`openspec/changes/pilot-response-integrity/{proposal,design,tasks}.md` + the five capability specs, against the
existing `Pilot::` code. No upstream EE source was consulted; all prompt wording, taxonomies, and naming are fresh.

## What was implemented, per spec section

### pilot-channel-length-limits

- **`Pilot::ReplyLengthBudget`** (`lib/pilot/reply_length_budget.rb`) — resolves the per-conversation character
  budget with the required precedence: (1) Instagram DM conversations (`additional_attributes['type'] ==
  'instagram_direct_message'`) → 1,000; (2) Twilio inboxes by `channel.medium` → 320 SMS / 1,600 WhatsApp;
  (3) channel-type table (Facebook 2,000, Instagram 1,000, LINE 5,000, SMS 320, Telegram 4,096, TikTok 6,000,
  WhatsApp 4,096); (4) default 10,000. Nil conversation → nil.
- **Budget disclosure** — `Custom::Pilot::AutopilotService#length_budget_section` adds a freshly worded
  "Reply length limit" instruction with the resolved number; omitted when no budget resolves (playground).
- **Rewrite-or-fail enforcement** — `Custom::Pilot::AutopilotService#enforce_length_budget` runs post-generation
  in `build_result`, on whichever run produced the final reply (including the forced tool-skip retry, which now
  also returns its run result). Measures `structured_reply.render(citation_urls)` (part texts + citation link
  markup). Within budget → untouched. Over budget → text-only budget = budget − markup length; non-positive →
  raise immediately (markup-only overflow, no rewrite). Otherwise exactly one `Pilot::ReplyShortener` pass;
  still-over → raise `AutopilotService::Error`, which the job's existing rescue routes to `handoff_on_error`.
- **`Pilot::ReplyShortener`** (`lib/pilot/reply_shortener.rb`) — single-turn (`max_turns: 1`), temperature-0
  `Agents::Runner` pass with a fresh instruction (shorten text only; preserve parts, facts, markdown, indexes).
  Programmatic verification: part-count change → raise; citations enabled and any per-part citation index list
  differs → raise. Original citations are re-attached regardless. The shortened output replaces
  `run_result.output` and the last assistant transcript entry so session recording matches delivery.

### pilot-multi-part-responses

Mostly landed in wave 1 (`pilot-agent-sessions-and-citations`): `lib/pilot/structured_reply.rb` (parsing,
normalization, degradation, `plain_text` assembly), prompt-side JSON contract (`citation_policy`), sentinel
evaluation on assembled plain text, sentinel stripping via `transform_texts` in the job, and parts persistence in
`additional_attributes['pilot_response_parts']`. This change added the missing **validation specs** (job spec:
ordered parts persisted, sentinels stripped from delivered part text, degraded single part stored) and kept the
contract consistent through the new enforcement path (shortened replies flow through the same
`structured_reply` → `Result` pipeline).

### pilot-handoff-consent

- `handover_policy` rewritten (fresh wording) as "Scope and handoff consent policy": offers only when the
  customer is genuinely stuck (never as a first response to an unanswered question); execution only on explicit
  customer request, accepted offer, or a guideline/guardrail mandate — with the mandate explicitly overriding
  the consent defaults; honesty rule forbidding any transfer claim unless the sentinel token ended that very
  reply. Pending-handoff state keeps using the existing `handoff_already_requested?` → `handover_pending_policy`
  suppression path (no re-offers, no re-emitted token).
- New `commitments_policy` section: no promises of work after the reply is sent unless completed in-turn via a
  tool; fallback is answer-from-verifiable / one clarifying question / offer-without-claiming.

### pilot-false-promise-detection

- **Setting** — `pilot_false_promise_guard_enabled` store_accessor on `Account` + whitelisted boolean in
  `account_settings_schema.rb`. Default off (nil).
- **`Pilot::PromiseGuard`** (`lib/pilot/promise_guard.rb`) — temperature-0 detector resolving its model via
  `Llm::Config.model_for(:promise_guard)` (env escape hatch → chat slot). Two-outcome verdict
  (safe / future_promise) + fixed taxonomy (`no_future_commitment`, `deferred_check_or_follow_up`,
  `ongoing_monitoring`, `later_contact_or_notification`, `background_or_offline_action`,
  `other_future_commitment`) + model. Detector errors or unparseable output → `:inconclusive`, never raises.
  Every detection logged (verdict, reason, model, account, conversation).
- **`Custom::Pilot::PromiseGuardService`** (`custom/app/services/custom/pilot/promise_guard_service.rb`) —
  orchestration: skips when setting off / blank reply / handoff already requested. On a promise verdict:
  regenerates exactly once through `AutopilotService` with the withheld draft appended to the run context
  (`repair_draft:` → last assistant entry in `conversation_history`) and a fresh internal repair directive
  (`repair_directive:` → `repair_directive_section` in the instructions; tools remain available). Re-verifies;
  safe → repaired reply delivered; still-flagged or unverifiable → suppress + `HandoffService` with
  `reason: "promise_guard:<category>"`, `reason_category: policy_refusal`, i18n'd customer message
  (`conversations.pilot.handoff_guard`) and an operator private note (`conversations.pilot.promise_guard_note`).
  Guard error after a detection fired → fail-safe handoff; error before any detection → original reply
  delivered. The whole guard never raises into delivery.
- **Job wiring** — `Pilot::AutopilotInferenceJob#perform` runs the guard between inference and
  `dispatch_inference_outcome`; `handed_off?` outcomes return early.

### pilot-agent-turn-budget

- `PILOT_AUTOPILOT_MAX_TURNS` kept as the surface; `DEFAULT_MAX_TURNS = 6` (≤ upstream's 10). Non-positive /
  unparsable values fall back to the default (already the case; now spec-pinned).
- Exhaustion wired explicitly: `turn_budget_exhausted?` checks
  `run_result.error.is_a?(::Agents::Runner::MaxTurnsExceeded)` (the ai-agents runner sets a non-nil output on
  exhaustion, so the generic `failed?` check alone was the only thing preventing partial-output delivery) and
  raises `Error` mentioning the turn budget → `handoff_on_error` in the job. Needs-investigation item resolved:
  ai-agents 0.9.1 signals exhaustion via `Agents::Runner::MaxTurnsExceeded` on `RunResult#error`.

## Files added

- `lib/pilot/reply_length_budget.rb`, `lib/pilot/reply_shortener.rb`, `lib/pilot/promise_guard.rb`
- `custom/app/services/custom/pilot/promise_guard_service.rb`
- `spec/lib/pilot/reply_length_budget_spec.rb`, `spec/lib/pilot/reply_shortener_spec.rb`,
  `spec/lib/pilot/promise_guard_spec.rb`, `spec/services/custom/pilot/promise_guard_service_spec.rb`

## Files changed

- `custom/app/services/custom/pilot/autopilot_service.rb` — budget section, enforcement, consent/commitments
  sections, repair directive/draft kwargs, MaxTurnsExceeded handling, tool-skip guard now returns the effective
  run result, `evaluate_signals` extraction (Metrics).
- `app/jobs/pilot/autopilot_inference_job.rb` — guard invocation.
- `app/models/account.rb`, `app/models/concerns/account_settings_schema.rb` — new setting.
- `config/locales/en.yml` — `conversations.pilot.handoff_guard`, `conversations.pilot.promise_guard_note`.
- `spec/services/custom/pilot/autopilot_service_spec.rb`, `spec/jobs/pilot/autopilot_inference_job_spec.rb` —
  new coverage (budget disclosure, consent/commitments, turn budget, enforcement, structured delivery, guard
  wiring).

No migrations; no schema change; no frontend change (task 12 deferred to API-only — no Pilot account-settings UI
surface exists in the dashboard).

## Test commands + results

- `RAILS_ENV=test bundle exec rspec spec/lib/pilot/reply_length_budget_spec.rb spec/lib/pilot/reply_shortener_spec.rb spec/lib/pilot/promise_guard_spec.rb spec/lib/pilot/structured_reply_spec.rb spec/services/custom/pilot/promise_guard_service_spec.rb spec/services/custom/pilot/autopilot_service_spec.rb spec/jobs/pilot/autopilot_inference_job_spec.rb` → **115 examples, 0 failures**.
- `bundle exec rubocop -a` on all 14 touched Ruby files → clean (15 auto-corrected, re-staged, committed).
- No JS/Vue files touched → eslint/vitest not applicable.

Every §Validation scenario from the five spec docs maps to a green example: budget precedence (6), shortener
invariants (8), detector contract (10), guard orchestration (10), enforcement matrix (7), turn budget (4),
consent/commitments wording (5), structured delivery/sentinels (3), job guard wiring (5).

## Deviations from spec

- **Citation verification in the shortener** — tasks.md §4 requires identical per-part citation indexes (raise on
  any violation) *and* re-attachment regardless; the channel-length spec's "altered or missing indexes →
  delivered parts carry originals" scenario is partially in tension with that. Implemented per tasks.md §4/§15:
  any per-part index difference raises (the response fails to the handoff path); re-attachment guarantees the
  delivered object always carries the original citations for every non-raising outcome.
- **Guard wiring point** — settled (per the needs-investigation note) on `Pilot::AutopilotInferenceJob` via a
  dedicated orchestrator service rather than inside `AutopilotService#perform`, so the playground and other
  service callers are unaffected and the guard sees the final post-rewrite reply text.
- **Guard handoff category** — `policy_refusal` (from the existing `HANDOFF_REASON_CATEGORIES` taxonomy), chosen
  to distinguish guard bailouts from both `customer_escalation` and `system_failure`; the fine-grained guard
  taxonomy rides in the `reason` string (`promise_guard:<category>`).
- **Private note** — the design open question was resolved in favor of posting one (task 10's proposal), with
  i18n'd copy.

## Blockers / deferrals

- **Task 12 (frontend toggle)** — deferred to API-only per the task's own escape clause: the dashboard has no
  Pilot account-settings surface (`pilot_auto_resolve_mode` etc. are also API/seed-only).
- **Task 19 (manual smoke test)** — deferred; needs a live LLM credential + running instance. Behaviors (a)–(d)
  are all covered by automated specs.
