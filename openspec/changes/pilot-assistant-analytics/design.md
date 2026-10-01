## Context

Konversio is a hard fork of Chatwoot v4.13.0 with the `enterprise/` overlay removed and Captain renamed to `Pilot::` throughout. The sibling change `pilot-conversation-outcomes` adds episode-grained outcome records (`pilot_conversation_outcomes`: one row per AI-involvement episode on a conversation, with lifecycle timestamps, reply facts, categorized handoffs, resolutions, and CSAT). This change builds the analytics surface on top of that data.

Upstream shipped this as two Enterprise releases: v4.16.0 added a Captain assistant overview and drill-down analytics (message- and reporting-event-derived), and v4.17.1 reworked the metrics to be episode-derived and added hours-saved, durable resolution rate, CSAT comparisons, resolution flow and trend views, and a cached LLM-generated overview summary. All of it is Enterprise-licensed, so this document is a **clean-room, requirements-level specification**: upstream code was read for functional understanding only. All wording, prompts, UI copy, and names in this change are original; the governed handoff-reason taxonomy is owned by the `pilot-conversation-outcomes` change and is referenced here only as "categorized handoff reasons," never enumerated. Where Konversio names appear (in tasks.md), they are new `Pilot::Analytics::*` names, not renamed upstream classes.

## Goals / Non-Goals

**Goals:**

- A per-assistant analytics API (overview, resolution flow, resolution trend, natural-language summary) under the existing Pilot namespace.
- A shared reporting-window service so every endpoint — and every drilldown — resolves the exact same current and comparison windows from the same `range` and `timezone_offset` inputs.
- Episode-derived funnel and outcome metrics with a stable cohort (grouped by when demand started), plus message-derived reply-activity metrics for active episodes.
- Current/previous/trend packing for every metric, with nulls (not zeros) for windows that predate outcome tracking.
- An administrator-only drilldown from a metric card to the exact conversations that produced it, reusing the shared reports drilldown serializer.
- A cached, LLM-generated natural-language summary of the structured report.
- A Pilot assistant overview page presenting all of the above.

**Non-Goals:**

- Knowledge-coverage statistics (approved/standalone FAQs, open suggestions, document counts) — owned by the `pilot-faq-suggestions` change; the overview page may link to it but does not spec it here.
- AI usage/quota consumption cards and limits banners — separate concern.
- Account-level or cross-assistant analytics; all endpoints are per-assistant.
- Modifying how outcomes are recorded — the episode table and its tracker are fixed inputs owned by `pilot-conversation-outcomes`.
- A legacy message/reporting-event-derived metrics builder (the upstream v4.16.0 approach); Konversio adopts the episode-derived model directly.

## Decisions

### Episode-derived metrics from day one

Upstream's first overview (v4.16.0) derived everything from message authorship and reporting events; v4.17.1 moved funnel and outcome metrics onto the episode table because episodes keep the cohort stable as later facts arrive (a handoff categorized after the fact still lands in the episode that demand started). Konversio skips the intermediate design: overview, flow, and trend metrics are computed from `pilot_conversation_outcomes`, grouped by episode start.

Alternatives considered:
- Port the v4.16.0 message/event-derived builder first for fidelity to the release line. Rejected: it is strictly superseded upstream, doubles the builder surface, and its reopen-rate computation had a known performance defect (fixed in v4.16.1, specced separately in `reporting-drilldowns`).
- Derive everything from episodes, including reply activity. Rejected: episode reply facts are snapshotted at terminal events, so active episodes would report stale reply counts; public-reply activity stays message-derived (sender is the assistant, outgoing, not private, within the window).

Rationale: one metrics model, stable cohorts, no known-defective intermediate.

### One shared reporting-window service

Every endpoint accepts `range` (a day count — 7, 30, 90 — or a named calendar period — this/last week, this/last month) and `timezone_offset` (the viewer's UTC offset in hours, as the existing reports API sends it). A single service resolves the current window and a mirrored previous window (preceding N days, or the preceding calendar week/month), anchored to the viewer's timezone so calendar boundaries land on the viewer's day. Unknown ranges fall back to the default 7-day window; unparseable offsets are flagged invalid (the summary endpoint rejects them with 422; other endpoints fall back to the server timezone). When the current month is longer than the previous, the comparison window is clamped to the previous month's end so no day is double-counted.

Alternatives considered:
- Per-endpoint window logic. Rejected: drilldowns must cover exactly the rows their stat card counted, which requires one canonical resolution.
- Server-timezone-only windows. Rejected: inconsistent with the existing reports API, which already sends viewer offsets.

### Trend packing with null-for-untracked semantics

Every metric is returned as `{ current, previous, trend }`. Trend semantics differ by metric kind: percent change for counts, point difference for rates, absolute difference for durations and scores. If either window starts before outcome tracking began, that window's value — and therefore the trend — is null, never a fabricated zero. The overview response also carries the tracking-start timestamp (earliest episode creation time, cached in Redis with a long TTL once present and a short TTL while empty) so the UI can explain the gap.

Alternatives considered:
- Return zeros for untracked windows. Rejected: a 0% auto-resolution rate for a window before tracking existed is misleading, and zero-denominator rates already read as 0.
- Hard-error on untracked ranges. Rejected: the range selector stays fully usable; the UI renders an "insufficient history" state instead.

### Estimated hours saved as an explicit assumption

Hours saved is an estimate, not a measurement: public AI replies in the window × an assumed average handling effort per reply, expressed in hours. Reporting data captures customer wait time, not agent handling effort, so the per-reply effort is a documented constant (default: two minutes per reply, the assumption level the ecosystem already anchors on) that must be labeled as an estimate in the UI.

Alternatives considered:
- Derive effort from first-response or resolution-time deltas. Rejected: conflates customer wait with agent effort and produces volatile numbers.
- Omit the metric. Rejected: it is the single most-asked-for headline number for AI support tooling.

### Durable resolution and CSAT baselines

Durable resolution rate measures quality, not just closure: of autonomous resolutions old enough to be judged (resolved at least a fixed durability window — seven days — ago), the share that did not reopen within that window. Windows too recent to judge return null, not a partial number.

CSAT is reported three ways: average rating on episodes the AI resolved autonomously, average rating on episodes where the AI was involved but a human finished, and an account-wide baseline of conversations with no AI involvement at all — so operators can compare like with like.

### Balanced, mutually exclusive flow branches

The resolution flow splits the involved cohort into exactly three terminal branches — resolved autonomously, handed off, closed with the team without either — whose counts sum to the cohort total, then splits autonomous resolutions into stayed-closed vs reopened-within-the-durability-window. Handoff reasons are shown as a distribution over the governed taxonomy (uncategorized handoffs grouped in a remainder bucket), sorted by count; the diagram highlights the top reasons and aggregates the rest so branch values stay balanced.

### Cached, schema-bounded natural-language summary

The summary endpoint feeds the structured report (period descriptor, overview metrics, resolution flow, resolution trend) to an LLM task service (`Pilot::BaseTaskService` subclass) with a structured-output schema bounding the response to at most three short observation strings. Results are cached in Redis under a versioned key that includes the account, the assistant's cache version, the resolved range, timezone, tracking-start timestamp, and account locale, with a one-hour TTL. Generation failures return 422 and are never cached. When the report shows no activity, the endpoint returns an empty list without calling the LLM. The prompt template is authored fresh for Konversio (`lib/pilot/prompts/`), stating the goal (surface the most decision-useful observations for a support lead, grounded in the supplied numbers) in original wording.

Alternatives considered:
- Client-side or uncached generation. Rejected: cost and latency per page load; the report only changes as outcomes land.
- Free-text paragraph output. Rejected: a bounded point list renders predictably in a card and is easier to keep grounded in the data.

### Administrator-only drilldowns over the shared serializer

Metric cards drill into conversations only for a supported metric set (conversations involved, auto-resolution rate, handoff rate, reopen-after-resolution rate). The drilldown endpoint is administrator-only (enforced in `Pilot::AssistantPolicy` and mirrored by hiding the affordance for non-admins), paginated (default 25, max 100 per page), and serializes records with the shared `V2::Reports::DrilldownRecordSerializer` from the `reporting-drilldowns` change so the existing drawer/card components render them unchanged. Each drilldown cohort is defined to match exactly what its card counted: the involved cohort is conversations with an AI-authored message in the window; the resolved cohort additionally excludes time-based bot resolutions on conversations that were also handed off; the reopened cohort is auto-resolved conversations that reopened at or after their AI resolution, with the reopen inside the window.

Alternatives considered:
- A Pilot-specific drilldown serializer. Rejected: duplicates rendering logic the reports drilldown already solved.
- Drilldowns for every metric. Rejected: rate metrics like durable resolution and CSAT have episode-grained denominators that don't map cleanly to a conversation list in v1; the four supported metrics cover the actionable cases.

## Risks / Trade-offs

- **Clean-room discipline** -> All expression here is original; implementers must not consult upstream Enterprise source while writing prompts, copy, or class internals. The handoff-reason taxonomy is owned and governed by `pilot-conversation-outcomes`; this change references it abstractly.
- **Single-scan aggregation complexity** -> Both windows' aggregates should be computed in one pass with conditional aggregation to bound query count; correctness of window predicates (especially the shared-boundary exclusion for day ranges) needs spec coverage.
- **Metric definitional drift** -> Overview cards, flow diagram, trend series, and drilldowns must agree; the shared window service plus shared classification predicates are the enforcement mechanism.
- **Summary staleness** -> The one-hour cache can lag fresh outcomes; the versioned key (including assistant cache version and tracking start) bounds this without a flush mechanism.
- **Empty-history UX** -> A fresh install has no episodes; every surface must render a deliberate empty state rather than zeros or errors.

## Migration Plan

1. Land `pilot-conversation-outcomes` and `reporting-drilldowns` first (hard dependencies).
2. Ship backend window/classification/report services with request specs, then the controller and routes.
3. Ship the summary generator and caching last among backend items.
4. Ship the frontend page behind normal Pilot feature availability; no feature flag required since Pilot itself is gated.
5. Rollback: remove routes, controller, services, and page; no data migrations exist in this change, so nothing needs unwinding.

## Open Questions

- needs investigation: confirm which reporting-event names the Konversio Pilot resolution path emits today (`conversation_pilot_inference_resolved` and/or the generic `conversation_bot_resolved`) so the drilldown resolved cohort and the overview aggregates count identical rows.
- needs investigation: whether Konversio's week-start convention should follow the viewer's locale rather than a fixed Sunday start; this spec fixes Sunday for consistency with existing reports, but a locale-aware start is a plausible follow-up.
