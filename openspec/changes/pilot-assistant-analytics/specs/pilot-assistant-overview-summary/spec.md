## Capability: pilot-assistant-overview-summary

Cached, LLM-generated natural-language observations over the structured overview report, with a rotating summary card on the overview page.

---

## ADDED Requirements

### Requirement: Summary generation from the structured report

The system SHALL expose an authenticated per-assistant overview-summary endpoint that generates a short list of natural-language observation points with an LLM task service. The model input MUST be an originally authored instruction supplying the assistant's name, the account's language, a human-readable description of the reporting period, and a structured payload containing the overview metrics, the resolution flow, and the resolution trend for the requested window. The response MUST be constrained by a structured-output schema to at most three points, each a short single-observation string.

#### Scenario: summary returns bounded points

- Given a report with activity in the window
- When the summary is requested
- Then the response contains a `points` list of at most three non-empty strings
- And each point is a single concise observation grounded in the report numbers

#### Scenario: no activity skips the LLM call

- Given a window in which the assistant handled no conversations in either window
- When the summary is requested
- Then the response contains an empty `points` list
- And no LLM call is made

#### Scenario: invalid timezone offset is rejected

- Given a summary request with an unparseable timezone offset
- When the endpoint is called
- Then the response is 422 Unprocessable Entity

---

### Requirement: Server-side caching

The endpoint MUST cache successful results server-side under a versioned cache key that incorporates the account, the assistant's cache version, the resolved range, the resolved timezone, the tracking-start timestamp, and the account locale, with a time-to-live of approximately one hour. Generation failures MUST NOT be cached and MUST be surfaced as 422 with an error payload.

#### Scenario: second request is served from cache

- Given a successful summary was generated for a range
- When the same summary is requested again within the TTL
- Then the cached points are returned without a new LLM call

#### Scenario: cache key varies with context

- Given a cached summary for one range and locale
- When the range, timezone, assistant version, tracking start, or account locale changes
- Then a new summary is generated instead of serving the stale entry

#### Scenario: failures are not cached

- Given the LLM call fails
- When the summary is requested
- Then the response is 422 with an error payload
- And a subsequent request retries generation

---

### Requirement: Summary card UI

The overview page MUST render a summary card with a greeting addressed to the current user, the observation points auto-rotating on an interval, manual previous/next controls that reset the rotation timer, a loading skeleton while generating, and a neutral empty state when no points are available. The rotating point region MUST be announced politely to assistive technology.

#### Scenario: points auto-rotate

- Given a summary with more than one point
- When the card renders
- Then the visible point advances automatically on an interval

#### Scenario: manual navigation resets rotation

- Given auto-rotation is active
- When the user activates the next or previous control
- Then the requested point is shown
- And the rotation interval restarts

#### Scenario: single point shows no controls

- Given a summary with exactly one point
- When the card renders
- Then no navigation controls are displayed

#### Scenario: loading and empty states are distinct

- Given the summary request is in flight
- Then a skeleton placeholder is shown instead of point text
- When the request completes with no points
- Then a neutral empty-state message is shown
