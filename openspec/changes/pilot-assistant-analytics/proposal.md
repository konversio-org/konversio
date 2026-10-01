## Why

The `pilot-conversation-outcomes` change gives Konversio episode-grained records of how Pilot AI involvement ends on each conversation (resolutions, categorized handoffs, reopens, CSAT), but nothing consumes that data. Operators still cannot answer "is the AI actually helping?" — how many conversations it touches, how often it resolves alone, how often and why it hands off, whether its resolutions stick, or how its CSAT compares to human-only conversations — without writing SQL by hand.

Upstream Chatwoot shipped a Captain assistant overview with drill-down analytics as an Enterprise feature in v4.16.0 and expanded it in v4.17.1 (hours-saved, durable resolution rate, CSAT comparisons, resolution flow and trend views, and a cached LLM-generated natural-language summary). Konversio needs the equivalent capability as a clean-room, MIT-licensed feature in the core tree.

## What Changes

- Add a per-assistant analytics API under the existing Pilot namespace with four endpoints:
  - **Overview**: a fixed set of metrics (conversations involved, autonomous resolutions and rate, handoff count and rate, estimated hours saved, reopen-after-resolution rate, conversation depth, durable resolution rate, autonomous/assisted/human-only CSAT, median time to resolution), each returned for the current window and a mirrored previous window with a derived trend.
  - **Resolution flow**: a balanced flow breakdown of the current window (involved → resolved autonomously / handed off / closed with the team; autonomous → stayed closed / reopened), plus a distribution of categorized handoff reasons.
  - **Resolution trend**: a day- or week-bucketed time series of involvement and autonomous resolution, with per-bucket resolution rates and a shifted comparison series.
  - **Overview summary**: an LLM-generated, natural-language list of the most decision-useful observations from the current report, cached server-side.
- Add an administrator-only drilldown endpoint that lists the paginated conversations behind a supported overview metric, reusing the shared reports drilldown serializer from the `reporting-drilldowns` change.
- Add a shared reporting-window service: day-count and named calendar ranges, viewer-timezone anchoring, a mirrored comparison window, and validation of the client-supplied timezone offset.
- Gate all episode-derived metrics on when outcome tracking began: windows that predate tracking return null values instead of misleading zeros, and the overview response exposes the tracking start timestamp.
- Add a Pilot assistant overview page to the dashboard: range selector, metric cards with trend indicators, resolution flow diagram with handoff-reason distribution, resolution trend chart with comparison, CSAT comparison panel, auto-rotating natural-language summary card, and an admin-only drilldown drawer on metric cards.

## Capabilities

### New Capabilities
- `pilot-assistant-overview-analytics`: Reporting windows, per-assistant overview metrics with current/previous/trend packs, episode classification rules, and tracking-start gating.
- `pilot-assistant-resolution-insights`: Resolution flow breakdown with handoff-reason distribution, and a bucketed resolution trend series with a comparison period.
- `pilot-assistant-drilldowns`: Administrator-only, paginated listing of the conversations behind a supported overview metric, with a drilldown drawer on the overview page.
- `pilot-assistant-overview-summary`: Cached, LLM-generated natural-language observations over the structured overview report, plus the summary card UI.

### Modified Capabilities
None.

## Impact

- `config/routes.rb` — new analytics endpoints under the existing `pilot` namespace.
- New controller `app/controllers/api/v1/accounts/pilot/assistant_analytics_controller.rb`; drilldown action on the existing pilot assistants controller.
- New services under `app/services/pilot/analytics/` (reporting window, outcome classifications, overview/flow/trend reports, drilldown query, summary generator) in the core tree.
- `app/policies/pilot/assistant_policy.rb` — analytics read permission for all account users; administrator-only drilldown permission.
- Frontend: new API client `app/javascript/dashboard/api/pilot/assistantAnalytics.js`; new overview route/page under `app/javascript/dashboard/routes/dashboard/pilot/`; new components under `app/javascript/dashboard/components-next/pilot/overview/`; `en.json` i18n only per project convention.
- Reads `pilot_conversation_outcomes`, `messages`, `reporting_events`, and `csat_survey_responses`; no new database tables.
- Depends on the `pilot-conversation-outcomes` change (episode data) and the `reporting-drilldowns` change (shared drilldown serializer).
- License: clean-room requirements-level specification of upstream Enterprise features (v4.16.0, v4.17.1) — no upstream code, prompts, copy, taxonomies, or naming is ported. See design.md.
