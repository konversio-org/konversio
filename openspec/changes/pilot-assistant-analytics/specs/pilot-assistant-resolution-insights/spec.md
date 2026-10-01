## Capability: pilot-assistant-resolution-insights

Resolution flow breakdown with a categorized handoff-reason distribution, and a bucketed resolution trend series with a comparison period, for a single Pilot assistant.

---

## ADDED Requirements

### Requirement: Resolution flow breakdown

The system SHALL expose an authenticated per-assistant resolution-flow endpoint that splits the current window's involved episode cohort into three mutually exclusive terminal branches — resolved autonomously, handed off, and closed with the team without either — whose counts MUST sum to the cohort total, and further splits autonomous resolutions into those that stayed closed and those that reopened within the durability window. The response MUST be renderable as a flow diagram of nodes and weighted links.

#### Scenario: branches are balanced

- Given an involved cohort of 100 episodes with 55 autonomous resolutions, 30 handoffs, and 15 closed with the team
- When the flow is built
- Then the three branch counts sum to 100
- And the autonomous branch splits into stayed-closed and reopened counts summing to 55

#### Scenario: untracked period returns an empty flow

- Given the current window starts before outcome tracking began
- When the flow is requested
- Then the response contains empty node and link lists and an empty reason distribution

---

### Requirement: Handoff-reason distribution

The flow response MUST include a distribution of handed-off episodes by their governed handoff-reason category, each entry carrying the category, count, and percentage of total handoffs, sorted by descending count. Episodes without a recorded category MUST be grouped into a single uncategorized bucket. The flow diagram MUST highlight the top reasons as individual branches and aggregate the remainder into a single other-reasons branch so link weights stay balanced.

#### Scenario: uncategorized handoffs are grouped

- Given handed-off episodes, some with and some without a recorded reason category
- When the distribution is built
- Then every categorized reason appears with its count and percentage
- And all uncategorized episodes appear under one bucket

#### Scenario: diagram aggregates the long tail

- Given a distribution with more categories than the diagram highlights
- When the flow diagram is built
- Then the top reasons appear as individual branches
- And the remaining reasons are aggregated into one branch whose weight equals their combined count

---

### Requirement: Resolution trend series

The system SHALL expose an authenticated per-assistant resolution-trend endpoint returning a bucketed time series over the current window: buckets are calendar days when the window spans up to 15 days and calendar weeks (weeks starting Sunday) otherwise, anchored to the viewer's timezone. Each bucket MUST carry its start and end dates, the involved episode count, the autonomous resolution count, and the current-window resolution rate (null when the bucket has no involved episodes).

#### Scenario: short windows bucket by day

- Given a 7-day window
- When the trend is requested
- Then the response granularity is daily
- And buckets partition the window without gaps or overlaps

#### Scenario: long windows bucket by week

- Given a 90-day window
- When the trend is requested
- Then the response granularity is weekly
- And week buckets start on Sunday in the viewer's timezone

#### Scenario: empty bucket rate is null

- Given a bucket with no involved episodes
- When the trend is serialized
- Then that bucket's resolution rate is null rather than zero

---

### Requirement: Comparison series shifted by whole weeks

The trend endpoint MUST include a comparison series built by shifting each bucket back by a whole number of calendar weeks chosen to cover the window's span, preserving weekdays and local clock times. Each bucket MUST carry its comparison bucket's dates and the comparison resolution rate, which MUST be null when the comparison period predates the start of outcome tracking.

#### Scenario: comparison preserves weekdays

- Given a daily bucket covering a Tuesday
- When the comparison bucket is computed
- Then the comparison bucket also covers a Tuesday

#### Scenario: comparison before tracking start is null

- Given outcome tracking began after the comparison window's start
- When the trend is requested
- Then every comparison resolution rate is null
- And current-window values are still returned
