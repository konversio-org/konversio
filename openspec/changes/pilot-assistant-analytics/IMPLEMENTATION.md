# pilot-assistant-analytics — Implementation Report

Status: implemented (backend + frontend + specs). Task 27's browser/manual UI smoke portion is deferred (see Deviations).

## What was implemented, per spec section

### pilot-assistant-overview-analytics

- **Shared reporting windows** — `Pilot::Analytics::ReportingWindow` (`app/services/pilot/analytics/reporting_window.rb`). Accepts `range` (day counts 7/30/90, named periods this/last week, this/last month; unknown → 7-day fallback) and `timezone_offset` in hours. Windows are computed on an offset-shifted "viewer wall clock" (UTC shifted by the offset) and shifted back at the edges, so calendar boundaries land exactly on the viewer's day without named-timezone DST pitfalls. Weeks start Sunday. Half-open `[since, until)` windows (shared boundary belongs to the current window). Month comparison windows clamp at the previous month's end. Unparseable non-blank offsets set `timezone_valid?` false and fall back to offset 0; blank offsets are treated as not-supplied. `period` exposes a label + start/end dates for the LLM prompt.
- **Episode classification rules** — `Pilot::Analytics::OutcomeClassifications` (`app/services/pilot/analytics/outcome_classifications.rb`): SQL-fragment predicates (`involved`, `autonomous`, `assisted`, `handoff`, `reopened`, `reopened_within_durability`, `judgeable`, `durable`) shared by `where(...)` and `COUNT(*) FILTER (WHERE ...)`, so cards, flow, trend, and drilldowns classify identically. Quota-blocked-before-reply episodes are not involved; quota transfers after AI participation count as handoffs; a human public reply before resolution defeats autonomy. Reopen time = `ended_at` (the recorder closes the open episode at reopen, so `ended_at` on a resolved episode is the reopen timestamp).
- **Overview metrics endpoint** — `Pilot::Analytics::OverviewReport` (`app/services/pilot/analytics/overview_report.rb`): full metric set (conversations involved, autonomous resolutions + rate, handoffs + rate, estimated hours saved, conversation depth, reopen-after-resolution rate, durable resolution rate, autonomous/assisted/human-only CSAT, median resolution seconds) for both windows, computed in one scan over episodes (conditional aggregation), one over messages, one over CSAT responses. Every metric packed `{ current, previous, trend }`; trend = percent change for counts (0 when previous is 0), point difference for rates, absolute difference for durations/scores. Windows starting before tracking began return null values and null trends; the response carries `tracking_started_at` (via the existing `Pilot::OutcomeTrackingHistory`, reused rather than duplicated).
- **Funnel/outcome specifics** — durable rate judges only resolutions ≥ 7 days old (null when nothing is judgeable); reopen rate shares the autonomous cohort and counts reopens (at/after the AI resolution) whose reopen falls inside the window.
- **Reply-activity metrics** — message-derived (outgoing, non-private, sender = the assistant): hours saved = replies × 2 min / 60 (documented `ASSUMED_HANDLING_MINUTES_PER_REPLY` constant, labeled as an estimate in the UI); conversation depth = replies / conversations that received ≥ 1 (0 when none).
- **CSAT comparison** — per-cohort averages over rated episodes only; human-only baseline excludes any conversation with any episode (any assistant) account-wide.
- **Assistant overview page** — `app/javascript/dashboard/routes/dashboard/pilot/PilotAssistantOverviewPage.vue` at route `pilot/assistants/:assistantId/overview` (name `pilot_assistant_overview`), linked from the Pilot settings page header. Range selector, metric cards with comparison + directional trend colored by per-metric favorability, flow/trend/CSAT/summary panels, admin-only drilldown affordance, insufficient-history hints on null metrics, deliberate empty states on every panel, abort + token-guard on all requests.

### pilot-assistant-resolution-insights

- **Resolution flow** — `Pilot::Analytics::ResolutionFlowReport`: balanced three-way split (autonomous / handed off / closed with team; sum = involved cohort) plus stayed-closed vs reopened-within-durability split of autonomous (sum = autonomous). Nodes + weighted links; handoff-reason distribution (category, count, percentage of total handoffs, uncategorized bucket, sorted desc); diagram highlights top 3 reasons and aggregates the rest into `other_reasons` (weights stay balanced). Untracked period → empty nodes/links/reasons.
- **Resolution trend** — `Pilot::Analytics::ResolutionTrendReport`: daily buckets ≤ 15-day windows, weekly (Sunday-start) otherwise, anchored to the viewer offset, gapless partition of the window; per bucket involved count, autonomous count, rate (null for empty buckets); comparison series shifted back `ceil(span/7)` whole weeks (weekdays preserved); comparison rates null when the comparison period predates tracking. Single outcome-table scan for all buckets (current + comparison).

### pilot-assistant-drilldowns

- `Pilot::Analytics::DrilldownQuery` (`app/services/pilot/analytics/drilldown_query.rb`): supported metrics exactly `conversations_involved`, `autonomous_resolution_rate`, `handoff_rate`, `reopen_after_resolution_rate`; unsupported → `UnsupportedMetricError` → 422. Cohorts per design: involved = conversations with an AI-authored public message in the window; auto-resolution = involved + countable AI resolution events (`conversation_pilot_inference_resolved` / `conversation_bot_resolved`, both confirmed present in `ReportingEventListener`) excluding time-based bot resolutions on conversations also handed off; handoff = involved + handoff event in window; reopen = conversations with a `conversation_opened` event in the window at/after an AI resolution (resolution may precede the window). Pagination: page default 1, per-page default 25, max 100 (clamped and reported). Meta: metric, current_page, per_page, total_count, since/until epoch bounds of the current window. Records serialized with `V2::Reports::DrilldownRecordSerializer`.
- Endpoint: member `GET /api/v1/accounts/:account_id/pilot/assistants/:id/drilldown` on `AssistantsController`; administrator-only via `Pilot::AssistantPolicy#drilldown?` (agents get 403; the UI hides the affordance for non-admins). Drawer UI (`OverviewDrilldownDrawer.vue`) reuses the `SidePanel` + `ReportDrilldownCard` patterns with loading/empty/error states and "Load more" pagination; rows navigate to conversations (inherited from the shared card).

### pilot-assistant-overview-summary

- `Pilot::Analytics::OverviewSummaryGenerator < Pilot::BaseTaskService` (`app/services/pilot/analytics/overview_summary_generator.rb`): builds the structured report (period descriptor, overview metrics, resolution flow, resolution trend), skips the LLM call entirely and returns `{ points: [] }` when both windows show no involvement, calls the model with a structured-output schema (`points` array, maxItems 3, required, no additional properties), strips/blank-filters/truncates returned points; LLM errors pass through for the controller to surface.
- New original prompt `lib/pilot/prompts/assistant_overview_summary.liquid` (Liquid, rendered with assistant name, account language, period descriptor, pretty-printed JSON report). Authored fresh for Konversio — no upstream wording.
- Endpoint: `GET .../analytics/overview_summary`; 422 on invalid timezone offset; successful results cached in `Redis::Alfred` for 1 hour under a versioned key (account id, assistant id + `cache_version`, resolved range, timezone offset, tracking-start epoch, account locale); failures render 422 and are never cached.
- Summary card (`OverviewSummaryCard.vue`): greeting with the current user's name, 6s auto-rotation, prev/next controls that restart the timer, no controls for a single point, polite `aria-live`, loading skeleton, neutral empty state.

### reporting-drilldowns task 16 (reopen-rate performance) — honored

- The reopen-after-resolution rate divides by the already-fetched autonomous-resolution total from the same single conditional-aggregation scan — no second query for the denominator, ever (and therefore no reopen query at all when nothing was resolved).
- All analytics endpoints are range-dependent metric endpoints, served separately from the existing range-independent FAQ/knowledge endpoints (`pilot/faq_suggestions`, owned by `pilot-faq-suggestions`); changing the range refetches only the analytics endpoints.

## Files added

Backend:
- `app/services/pilot/analytics/reporting_window.rb`
- `app/services/pilot/analytics/outcome_classifications.rb`
- `app/services/pilot/analytics/overview_report.rb`
- `app/services/pilot/analytics/resolution_flow_report.rb`
- `app/services/pilot/analytics/resolution_trend_report.rb`
- `app/services/pilot/analytics/drilldown_query.rb`
- `app/services/pilot/analytics/overview_summary_generator.rb`
- `app/controllers/api/v1/accounts/pilot/assistant_analytics_controller.rb`
- `lib/pilot/prompts/assistant_overview_summary.liquid`

Frontend:
- `app/javascript/dashboard/api/pilot/assistantAnalytics.js`
- `app/javascript/dashboard/routes/dashboard/pilot/PilotAssistantOverviewPage.vue`
- `app/javascript/dashboard/components-next/pilot/overview/{OverviewRangeSelector,OverviewMetricCard,ResolutionFlowPanel,ResolutionTrendPanel,CsatComparisonPanel,OverviewSummaryCard,OverviewDrilldownDrawer}.vue`
- Specs: `spec/services/pilot/analytics/*_spec.rb` (6 files), `spec/controllers/api/v1/accounts/pilot/assistant_analytics_controller_spec.rb`, `app/javascript/dashboard/components-next/pilot/overview/{OverviewSummaryCard,OverviewMetricCard}.spec.js`

## Files changed

- `config/routes.rb` — nested `resource :analytics` (4 GET actions) under `pilot/assistants`; member `get :drilldown`.
- `app/controllers/api/v1/accounts/pilot/assistants_controller.rb` — `drilldown` member action.
- `app/policies/pilot/assistant_policy.rb` — `overview?`, `resolution_flow?`, `resolution_trend?`, `overview_summary?` (all account users), `drilldown?` (admin only).
- `app/javascript/dashboard/routes/dashboard/pilot/routes.js` — overview route.
- `app/javascript/dashboard/routes/dashboard/pilot/AutopilotIndex.vue` — "Overview" entry button for the active assistant.
- `app/javascript/dashboard/i18n/locale/en/pilot.json` — `PILOT.OVERVIEW.*` strings (en only, per convention).

## Migrations

None (reads `pilot_conversation_outcomes`, `messages`, `reporting_events`, `csat_survey_responses` only).

## Test commands + results

- `RAILS_ENV=test bundle exec rspec spec/services/pilot/analytics/` — 56 examples, 0 failures.
- `RAILS_ENV=test bundle exec rspec spec/controllers/api/v1/accounts/pilot/assistant_analytics_controller_spec.rb` — 12 examples, 0 failures.
- `RAILS_ENV=test bundle exec rspec spec/services/pilot/ spec/controllers/api/v1/accounts/pilot/ spec/policies` — 363 examples, 0 failures.
- `pnpm test app/javascript/dashboard/components-next/pilot/overview/` — 2 files, 10 tests passed.
- `pnpm test app/javascript/dashboard/routes/dashboard/pilot/` — 2 files, 13 tests passed.
- `bundle exec rubocop -a` on all touched Ruby files — no offenses.
- `pnpm eslint` on all touched JS/Vue files — 0 errors (only repo-baseline warnings).
- Seeded runner smoke (test DB): hand-built episode set → overview packs, flow nodes, trend buckets, drilldown meta/payload, and no-activity summary short-circuit all verified against hand-computed numbers.

## Validation-scenario coverage map

- Window specs (`reporting_window_spec.rb`, 16 examples): every range kind, viewer-timezone anchoring, month clamp, invalid-offset flagging, unknown-range fallback, shared-boundary exclusion.
- Report specs: quota-block pre/post participation, human-reply-before-resolution, reopen timing vs durability window, untracked-period nulls, human-only CSAT baseline exclusion, trend semantics per metric kind, balanced flow branches, uncategorized bucket, long-tail aggregation, daily/weekly bucketing, weekday-preserving comparison, comparison-before-tracking nulls, drilldown cohorts (timer-closure exclusion, reopen-requires-AI-resolution), pagination clamps, meta epoch bounds, summary schema bounding/strip/no-activity skip.
- Request specs (12 examples): response shapes, agent read access, non-admin drilldown forbidden, 422 on invalid offset and unsupported metric, per-page clamp, summary cache hit/miss/range-variance, failures not cached.

## Deviations from spec

- **Tracking history service (task 3)**: reused the existing `Pilot::OutcomeTrackingHistory` (merged with `pilot-conversation-outcomes`) instead of adding a duplicate `pilot/analytics/tracking_history.rb` — identical caching semantics (short TTL while empty, long TTL once set).
- **Trend chart**: rendered with Tailwind/CSS bars (grouped involved/autonomous bars + rate mode + tooltips with comparison values) rather than introducing a chart library, per the repo's MVP/styling guidance.
- **Overview gating strictness**: per spec, a window whose start predates tracking start returns nulls — during the first days after tracking begins, current windows will show "insufficient history" until the window start passes the tracking start. This is the literal spec semantics and is covered by specs.
- **Timezone anchoring**: implemented as a pure offset shift rather than named-zone lookup (the reports-API helper can match DST-observing zones whose historical offsets differ — e.g. offset 0 matched the Azores and broke month boundaries). Semantics for the viewer's current offset are identical; DST transitions inside a window are not modeled.

## Blockers / deferrals

- **Task 27 (manual smoke test)**: backend seeded smoke was run via `rails runner` against the isolated test DB with hand-computed numbers (all matched). The browser-based UI smoke (cards, flow diagram, summary rotation, admin drawer against a running server) is deferred — no dev server was exercised in this worktree.
- The two known pre-existing failure groups (`pilot/custom_tools_controller_spec.rb` POST /test, `Pilot::Tools::Executor` network/SSRF specs) were not touched and not re-verified beyond the pilot suites above (which do not include them... they live under spec/controllers/api/v2 — outside the suites run here).
