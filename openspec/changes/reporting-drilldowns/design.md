## Context

Report charts (`ReportContainer.vue` + `BarChart.vue` on the overview, agent, inbox, label, team, and bot report pages) render timeseries aggregates produced by the v2 reports API (`Api::V2::Accounts::ReportsController`, `V2::Reports::*` builders over `conversations`, `messages`, and `reporting_events`). There is no way to go from a bar to its constituent records. Upstream Chatwoot added exactly this in v4.16.0 (PR #14626) with a follow-up drawer-position fix (PR #14919); both live entirely in the core (MIT) tree and are unchanged between v4.16.0 and v4.18.0, so the v4.18.0 file set is a stable port reference.

The second changelog item, "performance fix for report reopen-rate calculations" (v4.16.1, PR #15122), touches only upstream `enterprise/` (Captain) files plus Captain frontend routes. Konversio removed `enterprise/` and has no Pilot assistant overview stats builder today, so there is no existing Konversio code to patch — the item is specced as requirements for when the Pilot overview surface lands.

### License axes (per sub-item)

- **Conversation and message drilldowns (v4.16.0, PRs #14626, #14919): MIT.** Core-tree upstream code; verbatim porting is legal. The spec references upstream files and behavior at code level.
- **Reopen-rate calculation performance fix (v4.16.1, PR #15122): EE → clean-room.** The upstream diff is entirely `enterprise/app/**`, `spec/enterprise/**`, and Captain frontend paths. Despite being assigned under this change's MIT umbrella, the reference material is EE-licensed, so this change expresses the requirement in original wording against Konversio's `Pilot::` namespace and never ports the code. (Flagged for the parity coordinator: this sub-item may belong on an EE axis.)

## Goals / Non-Goals

**Goals:**

- Administrator-only drilldown endpoint on the v2 reports API returning the records behind one chart bar, paginated and throttled.
- Support every public report metric the charts render: `conversations_count`, `incoming_messages_count`, `outgoing_messages_count`, `avg_first_response_time`, `avg_resolution_time`, `reply_time`, `resolutions_count`, `bot_resolutions_count`, `bot_handoffs_count`.
- Support all report dimensions: `account` (default), `inbox`, `agent`, `label`, `team`.
- Drawer UX on report bar charts: click a non-zero bar, browse records, paginate, move between bars, click through to the conversation (and message).
- Port the MIT upstream implementation with Konversio-appropriate adaptations (branding-free i18n, no enterprise hooks).
- Clean-room requirements for the Pilot reopen-rate performance fix.

**Non-Goals:**

- Drilldowns on CSAT, SLA, live, or heatmap reports (upstream did not add them there either).
- Drilldowns for non-administrator roles (upstream gates to administrators; keep that).
- The Captain/Pilot assistant overview drilldown analytics (upstream PRs #14920, #15725) — separate EE clean-room work, out of scope here except for the reopen-rate calculation requirements.
- The broader upstream v4.17/v4.18 reports refactor (`Reports::DataSource`, `Reports::RawDataSource`, rollup tables) — only the `Reports::ReportMetricRegistry` metadata the drilldown needs is in scope; needs investigation: whether the registry should be introduced standalone here or deferred to the larger refactor change.
- Chart library migration (upstream later moved `BarChart.vue` to `@chatwoot/viz`). Konversio still uses the vue-chartjs `BarChart`; the click emission must be implemented against Konversio's current chart component. needs investigation: exact click-event API on Konversio's chart setup.

## Decisions

### Port the upstream MIT implementation directly

The drilldown backend (`drilldown_builder.rb`, `drilldown_record_serializer.rb`, `drilldown_timestamp_validator.rb`, controller action, route) and frontend (`useReportDrilldown.js`, `ReportDrilldownDrawer.vue`, `ReportDrilldownCard.vue`, API helper, i18n) are core-tree MIT code, stable since v4.16.0. Verbatim porting with renaming only where Konversio diverges is the lowest-risk path.

Alternatives considered:
- Reimplement from requirements. Adds risk of behavioral drift (bucket math, event-name mapping, distinct-conversation counting) for no licensing benefit — the code is MIT.
- Wait for the larger v4.17/v4.18 reports refactor and port drilldowns on top of it. The drilldown builder at v4.18.0 depends only on the metric registry and existing models, not on rollup tables, so it can land first.

Rationale: legal, stable, and reviewable against upstream diffs.

### Bucket semantics: intersect bucket window with requested range

A drilldown request carries `bucket_timestamp`, `since`, `until`, and `group_by`. The effective record window is `[max(bucket_start, since), min(bucket_end, until))`, where `bucket_end` is the bucket start plus one group-by period (hour/day/week/month/year), computed in the timezone derived from `timezone_offset`. Validation rejects requests where the bucket does not overlap the requested range, where timestamps are not integers, or where `since >= until` (422).

Rationale: matches upstream (`Reports::DrilldownTimestampValidator`, `V2::Reports::DrilldownBuilder#bucket_range`) and keeps edge buckets (partial first/last bars) consistent with what the chart actually rendered.

### Metric → record-source mapping via a metric registry

Introduce `Reports::ReportMetricRegistry` describing each public metric: API name, aggregate type (count/average), raw `reporting_events` event name, and raw count strategy. The drilldown resolves records as:

- `conversations_count` → `conversations` created in the bucket (record_type `conversation`).
- `incoming_messages_count` / `outgoing_messages_count` → `messages` of that direction in the bucket (record_type `message`).
- `resolutions_count`, `avg_resolution_time` → `conversation_resolved` reporting events; `avg_first_response_time` → `first_response` events; `reply_time` → `reply_time` events (record_type `conversation`, except `avg_first_response_time` and `reply_time`, which surface as `message` records — see serializer decision).
- `bot_resolutions_count` → `conversation_bot_resolved` events excluding conversations that also have a `conversation_bot_handoff` event in the full requested range.
- `bot_handoffs_count` → one row per distinct conversation with a `conversation_bot_handoff` event (latest event per conversation), so counts match the chart aggregate.

Alternatives considered:
- Hardcode the mapping in the builder. Upstream started there and centralized it; the registry is also what later report refactors consume, so introducing it now avoids a second migration of the same knowledge.

Rationale: single source of truth for metric metadata; matches upstream v4.18.0 shape.

### Response envelope and record serialization

Response is `{ meta, payload }`. `meta` carries the metric, record type, resolved bucket bounds (unix), `current_page`, `per_page`, `total_count`, and `conversation_count` (distinct conversations in the bucket — used by the UI subtitle; equals `total_count` for conversation metrics). Payload rows carry a `record_type`, a compact conversation object (id, display_id, contact/inbox/assignee names, status, created_at, last_activity_at, last message preview), an optional message object (id, content, message_type, sender name, created_at), `metric_value` (event value or business-hours value when `business_hours` is set), `occurred_at`, and `event_name` for event-backed conversation rows.

For `avg_first_response_time` and `reply_time`, the serializer infers the message that ended the event (outgoing/template message in the same conversation within ±1s of `event_end_time`; for first-response events attributed to a user, the sender must match) and renders it as a message row, falling back to a conversation row. Latest-message previews are batch-loaded with one `DISTINCT ON (conversation_id)` query per page to avoid N+1.

Rationale: this is what makes first-response/reply-time bars drill into the actual reply message; port as-is from upstream.

### Administrator-only access, enforced server-side and in the UI

The controller returns 401 unless `Current.account_user.administrator?`. The frontend only activates bar clicking for administrators and shows an "administrators only" alert otherwise.

Alternatives considered:
- Allow agents to drill down. Record lists expose contact names and message content across inboxes; upstream deliberately gated this to admins, and loosening it is a separate product decision.

Rationale: match upstream; least-surprise permission model for a data-exposing endpoint.

### Dedicated, tighter rate limit

Add a rack-attack throttle keyed on `uid` (or API access token) plus account id for the drilldown path, default `max(RATE_LIMIT_REPORTS_API_USER_LEVEL / 10, 1)` requests per minute (10 with default settings), overridable via `RATE_LIMIT_REPORTS_DRILLDOWN_API_USER_LEVEL`.

Rationale: drilldown queries scan messages/reporting_events per bucket; upstream throttles an order of magnitude tighter than the general reports API. Port as-is.

### Frontend state: composable with stale-response protection

`useReportDrilldown` owns drawer data: an AbortController per request, a monotonic request token, and a request fingerprint so late or superseded responses are dropped; page 1 replaces records, later pages append ("Load more" while `records.length < total_count`). `ReportContainer` maps a bar click to `(metric, bucketTimestamp, index)`, opens the drawer, and enables previous/next bar buttons that skip buckets whose chart value is zero. Cards deep-link to the conversation route; message rows append the message id so the conversation view scrolls to the message.

Rationale: direct port of upstream's proven UX, including the RTL/LTR drawer-position fix (#14919) via the shared side-panel component.

### Reopen-rate fix: clean-room requirements against `Pilot::` (EE source)

Upstream's fix (a) computes reopen rate as reopened-conversations divided by the already-fetched resolved-conversations total instead of querying the denominator twice, (b) skips the reopen query when the resolved count is zero, and (c) splits range-dependent reporting metrics from range-independent FAQ stats into separate endpoints so range changes refetch only metrics. We spec these as behavioral requirements for Konversio's future Pilot assistant overview (`Pilot::` namespace, core tree, `pilot_`-prefixed tables if any). No upstream code, class names, or file layout is carried over; per the repo's audit guidance, Pilot is an independently re-expressed AI layer.

Rationale: the upstream diff is EE-licensed (`enterprise/`); verbatim porting is not permitted even though the behavior is desirable.

## Risks / Trade-offs

- **Registry introduced ahead of the reports refactor** -> Keep `Reports::ReportMetricRegistry` minimal (drilldown needs only name/aggregate/raw event/count strategy); if the rollup refactor lands later it extends the same registry rather than replacing it.
- **Chart component divergence** -> Konversio's `BarChart.vue` predates upstream's `@chatwoot/viz` migration; implement `itemClick` emission on the existing vue-chartjs wrapper and isolate the mapping in `ReportContainer`.
- **Query cost on large buckets** -> Rely on existing indexes plus the tight throttle; paginate at 25/page (max 100). Add indexes only if production query plans prove them necessary.
- **Admin-only gating surprises agents** -> Documented in the spec and UI copy; upstream-consistent.

## Migration Plan

1. Ship backend endpoint + throttle first (additive, no migrations).
2. Ship frontend drawer behind the same deploy; bar clicking activates only for administrators.
3. Rollback by reverting both; no data changes to unwind.
4. Reopen-rate requirements are dormant until a Pilot assistant overview surface exists; no runtime change from this item today.

## Open Questions

- needs investigation: Konversio's `BarChart.vue` click handling — exact event payload from vue-chartjs for mapping bar index → bucket timestamp.
- needs investigation: whether `Reports::ReportMetricRegistry` lands standalone here or inside a separate reports-refactor change (coordinate with the parity coverage doc owner).
- needs investigation: the target shape of the Pilot assistant overview (which endpoints exist, where reopen rate is computed) — the reopen-rate requirements assume a surface Konversio has not built yet.
