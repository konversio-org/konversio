## Why

Report charts in Konversio are read-only aggregates: an administrator can see that 42 conversations were created on a given day or that average first response time spiked last week, but cannot answer *which* conversations or messages produced that bar without leaving Reports and reconstructing the set by hand in the conversation list. Upstream Chatwoot v4.16.0 shipped conversation and message drilldowns for reports (chatwoot/chatwoot#14626, core/MIT), and v4.16.1 shipped a performance fix for report reopen-rate calculations (chatwoot/chatwoot#15122). Konversio, forked at v4.13.0, has neither.

## What Changes

- Add `GET /api/v2/accounts/:account_id/reports/drilldown`, an administrator-only endpoint that returns the paginated conversations or messages behind a single chart bar (time bucket) for a given report metric, dimension (account, inbox, agent, label, team), and date range.
- Add a drilldown backend: `V2::Reports::DrilldownBuilder`, `V2::Reports::DrilldownRecordSerializer`, `Reports::DrilldownTimestampValidator`, and a `Reports::ReportMetricRegistry` that centralizes public report-metric metadata (raw reporting-event name, aggregate type, count strategy).
- Add a per-user, per-account rack-attack throttle for the drilldown endpoint, an order of magnitude tighter than the general reports throttle.
- Make report bar charts clickable: clicking a non-zero bar opens a right-side drawer listing the contributing records, with loading/empty/error states, "Load more" pagination, previous/next bar navigation (skipping empty buckets), and rows that link into the conversation view (message rows deep-link to the message).
- Add stale-response protection for drilldown fetches (abort + request tokens) so rapid bar clicks never render out-of-order pages.
- Include the upstream follow-up fix for drawer positioning in RTL/LTR layouts (chatwoot/chatwoot#14919).
- Performance fix (v4.16.1, clean-room — see design.md): when a Pilot assistant overview reports a reopen-after-resolution rate, the calculation SHALL reuse the already-fetched resolved-conversation count as the denominator, skip the reopen query entirely when no conversations were resolved, and serve range-dependent reporting metrics separately from range-independent FAQ/knowledge stats so range changes refetch only the metrics.

## Capabilities

### New Capabilities
- `report-drilldowns`: Administrator-facing drilldown from any report bar into the underlying conversation/message records, backed by a dedicated paginated, throttled v2 API and a drawer UI on report charts.
- `pilot-assistant-reopen-rate-performance`: Requirements for computing a Pilot assistant reopen-after-resolution rate without redundant queries, and for splitting range-dependent overview metrics from range-independent stats. Conditional on a Pilot assistant overview surface (tracked separately); specced clean-room.

### Modified Capabilities
None.

## Impact

- `config/routes.rb` (new v2 reports collection route)
- `app/controllers/api/v2/accounts/reports_controller.rb` (new `drilldown` action, param validation)
- `app/builders/v2/reports/` (new `drilldown_builder.rb`, `drilldown_record_serializer.rb`)
- `app/services/reports/` (new `report_metric_registry.rb`, `drilldown_timestamp_validator.rb`)
- `config/initializers/rack_attack.rb` (new drilldown throttle)
- `app/javascript/dashboard/api/reports.js` (new `getDrilldown` with abort signal)
- `app/javascript/dashboard/routes/dashboard/settings/reports/` (`ReportContainer.vue`, `Index.vue`, `BotReports.vue`, `components/WootReports.vue`; new `components/ReportDrilldownDrawer.vue`, `components/ReportDrilldownCard.vue`, `composables/useReportDrilldown.js`)
- `app/javascript/shared/components/charts/BarChart.vue` (bar click emission)
- `app/javascript/dashboard/i18n/locale/en/report.json` (new DRILLDOWN block; en only per project convention)
- No database migrations; reads existing `conversations`, `messages`, and `reporting_events` tables.
- Pilot assistant overview code (reopen-rate item): no Konversio target files exist yet — see design.md.
