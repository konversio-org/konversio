## Capability: pilot-assistant-overview-analytics

Per-assistant overview metrics computed from Pilot outcome episodes and reply activity, resolved over viewer-aware reporting windows, each returned as a current/previous/trend pack.

---

## ADDED Requirements

### Requirement: Shared reporting windows

The system SHALL resolve analytics windows from a `range` parameter and a viewer `timezone_offset` (the viewer's UTC offset in hours, as the existing reports API sends it). Accepted ranges are the day counts 7, 30, and 90 and the named calendar periods this week, last week, this month, and last month. The system MUST resolve a mirrored previous window of equal span immediately preceding the current window, anchored to the viewer's timezone so calendar boundaries land on the viewer's day.

#### Scenario: day-count range resolves two adjacent windows

- Given a viewer requests range "7"
- When the window is resolved
- Then the current window covers the last 7 days ending now in the viewer's timezone
- And the previous window covers the 7 days immediately before that

#### Scenario: named calendar period resolves calendar boundaries

- Given a viewer requests range "this_month"
- When the window is resolved
- Then the current window starts at the first instant of the viewer's current calendar month
- And the previous window covers the preceding calendar month up to the same elapsed offset, clamped to that month's end so no day is counted twice

#### Scenario: unknown range falls back to the default

- Given a viewer requests an unsupported range value
- When the window is resolved
- Then the 7-day window is used

#### Scenario: invalid timezone offset is flagged

- Given a viewer supplies a timezone offset that cannot be parsed as hours
- When the window is resolved
- Then the window flags the offset as invalid and falls back to the server timezone

---

### Requirement: Overview metrics endpoint

The system SHALL expose an authenticated per-assistant overview endpoint under the Pilot namespace returning the full metric set for both windows plus the timestamp at which outcome tracking began. Every metric MUST be packed as `{ current, previous, trend }`. The endpoint MUST be available to all account users who can view the assistant.

#### Scenario: overview returns packed metrics and tracking start

- Given a Pilot assistant with recorded outcome episodes
- When an account user requests the overview for range "30"
- Then the response contains a packed `{ current, previous, trend }` object for every metric
- And the response contains the tracking-start timestamp

#### Scenario: trend semantics differ by metric kind

- Given current and previous values for a count metric, a rate metric, and a duration metric
- When trends are derived
- Then count metrics use percent change relative to the previous window (0 when the previous value is 0)
- And rate metrics use the point difference between windows
- And duration and score metrics use the absolute difference between windows

#### Scenario: untracked windows return null, not zero

- Given outcome tracking began 10 days ago
- When a metric's previous window starts before tracking began
- Then that window's value is null
- And the metric's trend is null

---

### Requirement: Episode classification rules

The system MUST classify each outcome episode using shared query-time rules: an episode is *involved* when the AI posted at least one public reply, or when it was handed off for any reason other than a transfer caused by usage-quota exhaustion that occurred before any AI reply; *autonomous* when it was resolved, the AI replied, no handoff occurred, and no human public reply preceded the resolution; *assisted* when it was involved and resolved but not autonomous; a *handoff* when it was involved and carries a handoff timestamp (including quota-related transfers after AI participation).

#### Scenario: quota-blocked episode without AI reply is not involved

- Given an episode whose only handoff was caused by usage-quota exhaustion and in which the AI never replied
- When classifications are applied
- Then the episode is not counted as involved, autonomous, assisted, or handed off

#### Scenario: quota transfer after AI participation is a real handoff

- Given an episode in which the AI replied and was later transferred due to quota exhaustion
- When classifications are applied
- Then the episode is involved and handed off

#### Scenario: human reply before resolution defeats autonomy

- Given an episode resolved after a human posted a public reply
- When classifications are applied
- Then the episode is involved and assisted, but not autonomous

---

### Requirement: Funnel and outcome metrics

The overview MUST include: conversations involved (episode count), autonomous resolutions and their rate over the involved cohort, handoff count and rate over the involved cohort, reopen-after-resolution rate (share of autonomous resolutions that later reopened), durable resolution rate, and median seconds from episode start to resolution across resolved involved episodes.

#### Scenario: durable resolution rate judges only old-enough resolutions

- Given autonomous resolutions, some resolved more than seven days ago and some fewer
- When the durable resolution rate is computed
- Then only resolutions at least seven days old form the denominator
- And the numerator is those that did not reopen within seven days of resolution
- And when no resolution is old enough to judge, the rate is null

#### Scenario: reopen rate shares the autonomy cohort

- Given autonomous resolutions in the window, of which some reopened afterwards
- When the reopen-after-resolution rate is computed
- Then the denominator is the autonomous resolution count
- And the numerator counts reopen events at or after the AI resolution and within the window

---

### Requirement: Reply-activity metrics

The overview MUST derive public-reply activity from message authorship (outgoing, non-private messages authored by the assistant) rather than episode snapshots, and MUST include: estimated hours saved (public AI replies in the window multiplied by a documented assumed handling effort per reply, expressed in hours) and conversation depth (public AI replies divided by the number of conversations that received at least one, zero when none).

#### Scenario: hours saved scales with public reply count

- Given 300 public AI replies in the window and an assumed effort of two minutes per reply
- When hours saved is computed
- Then the result is 10 hours

#### Scenario: hours saved is presented as an estimate

- Given the overview page renders the hours-saved card
- Then the card is labeled as an estimate based on an assumed per-reply effort

---

### Requirement: CSAT comparison metrics

The overview MUST report average CSAT ratings for three cohorts: episodes resolved autonomously, episodes resolved with AI involvement but not autonomously, and — as an account-wide baseline — conversations in the window with no AI involvement at all. Averages MUST ignore unrated episodes and be null when no rating exists.

#### Scenario: human-only baseline excludes AI-involved conversations

- Given CSAT responses on AI-involved conversations and on conversations the AI never touched
- When the human-only baseline is computed
- Then only conversations with no AI involvement contribute

#### Scenario: cohort averages stay separate

- Given CSAT ratings on both autonomous and assisted episodes
- When the overview is computed
- Then autonomous and assisted averages are computed independently and reported as separate metrics

---

### Requirement: Assistant overview page

The dashboard SHALL provide a Pilot assistant overview page with a range selector offering all supported ranges, metric cards showing the current value with a comparison-period value and a directional trend indicator colored by whether the movement is favorable for that metric, and dedicated panels for the resolution flow, resolution trend, CSAT comparison, and natural-language summary. The page MUST refetch on range or assistant changes, MUST abort or token-guard in-flight requests so superseded responses never render, and MUST render deliberate empty and insufficient-history states when no episodes exist or the tracking-start timestamp postdates the selected window.

#### Scenario: range change refetches all panels

- Given the overview page is showing the default range
- When the user selects a different range
- Then overview, flow, trend, and summary data are refetched for that range
- And responses from the previous selection cannot overwrite the new data

#### Scenario: null metric renders insufficient-history hint

- Given a metric whose current window predates tracking start
- When the metric card renders
- Then it shows an insufficient-history hint instead of a numeric value
- And no trend indicator is shown

#### Scenario: fresh install shows an empty state

- Given an assistant with no recorded outcome episodes
- When the overview page loads
- Then every panel renders its empty state
- And no error is surfaced to the user
