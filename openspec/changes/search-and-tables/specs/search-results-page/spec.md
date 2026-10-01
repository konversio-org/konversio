## Capability: search-results-page

Reliability and polish improvements to the existing global search results page (tabs: All, Contacts, Conversations, Messages, Articles): deduplicated pagination, deterministic ordering, richer payloads, safe highlighting, and exact-timestamp tooltips.

---

## ADDED Requirements

### Requirement: paginated search results SHALL be deduplicated by record id

When appending a fetched page of search results to an existing result list, the store MUST drop records whose id already appears in the list, for each of the four result types (contacts, conversations, messages, articles).

#### Scenario: overlapping pages do not duplicate records

- Given the messages tab already shows message ids [10, 9, 8]
- And a new message arrives before the next page is fetched, shifting offsets
- When "Load more" returns ids [8, 7, 6]
- Then the list becomes [10, 9, 8, 7, 6] with no duplicate of id 8

---

### Requirement: each result tab SHALL track hasMore from the raw API page size

Each search action MUST set a `hasMore` UI flag for its tab to true exactly when the API returned a full page (15 records), independent of how many records survived deduplication. The "Load more" control MUST be shown only when the tab has records and `hasMore` is true.

#### Scenario: full page signals more results

- Given the conversations tab fetched a page of exactly 15 conversations
- Then `hasMore` for conversations is true
- And the "Load more" control is visible

#### Scenario: partial page signals end of results

- Given the conversations tab fetched a page of 7 conversations
- Then `hasMore` for conversations is false
- And the "Load more" control is not visible

#### Scenario: fully deduplicated page still reports hasMore correctly

- Given a fetched page of 15 contacts of which 15 were already in the list (all deduplicated away)
- Then `hasMore` for contacts is still true
- Because the raw page was full, more pages may exist

---

### Requirement: failed page fetches SHALL NOT consume the page number

Search actions MUST report success or failure to the caller; when a "Load more" dispatch fails, the view MUST roll the tab's page counter back so a retry re-fetches the same page.

#### Scenario: retry after failure fetches the same page

- Given the messages tab is on page 1
- When "Load more" for page 2 fails
- And the user clicks "Load more" again
- Then page 2 is requested again, not page 3

---

### Requirement: message search ordering SHALL be deterministic

Message search results MUST be ordered by `created_at` descending with message `id` descending as a tiebreaker, in both the full-text search path and the ILIKE fallback path.

#### Scenario: equal timestamps return in stable order across pages

- Given three messages with identical `created_at` matching the query
- When the user fetches page 1 and then page 2
- Then no message appears on both pages and no matching message is skipped between pages

---

### Requirement: message search payloads SHALL include the message id and a subject fallback

Message search results MUST include the message `id`. The email subject in the payload MUST fall back to the conversation's stored mail subject when the message itself carries no subject.

#### Scenario: payload contains id

- Given a message matches a search
- Then its search payload includes a non-null `id`

#### Scenario: subject falls back to conversation metadata

- Given a matching message with no `email.subject` content attribute
- And its conversation has a stored mail subject
- Then the search payload exposes the conversation's mail subject as the email subject

---

### Requirement: conversations without messages SHALL NOT break search responses

Conversation search serialization MUST skip the first-message partial when the conversation has no messages.

#### Scenario: empty conversation appears in results

- Given a conversation with zero messages matches a search
- When the conversations search endpoint renders results
- Then the response succeeds and includes the conversation without a message block

---

### Requirement: relative dates in result items SHALL expose an exact timestamp on hover

Contact, conversation, message, and article result items MUST show a localized exact date-time tooltip when hovering the relative timestamp ("2 days ago"). The exact timestamp MUST format in the user's dashboard locale using the Gregorian calendar, MUST be empty when there is no timestamp, and SHOULD be produced by a shared composable that caches `Intl.DateTimeFormat` instances per locale.

#### Scenario: hover shows exact date

- Given a conversation result shows "3 days ago"
- When the user hovers the relative date
- Then a tooltip shows the exact localized date and time (e.g. "Feb 2, 2026, 8:10 AM")

#### Scenario: missing timestamp yields no tooltip content

- Given a result item with no timestamp value
- Then the exact-timestamp formatter returns an empty string

---

### Requirement: search-term highlighting SHALL render escaped plain text

Message result highlighting MUST convert message content to plain text, HTML-escape it, and inject only the highlight `<span class="searchkey--highlight">` markup, so message content can never introduce HTML into the result view. A message whose transcript or content contains HTML-like text MUST display that text literally.

#### Scenario: HTML-like content is displayed literally

- Given a matching message whose content contains the literal text `<img src=x onerror=alert(1)>`
- When the message result renders with a search term
- Then the literal characters are visible as text
- And no image element or script executes

#### Scenario: empty search term shows unhighlighted escaped text

- Given a message result rendered without a search term
- Then the content renders as escaped text with no highlight spans

---

### Requirement: voice-call message results SHALL display the call transcript

When a matching message is a voice call with a transcript, the result MUST show the transcript text instead of the generic call label.

#### Scenario: transcript shown for voice call result

- Given a voice-call message whose call has a transcript containing the search term
- When the message appears in search results
- Then the result body shows the transcript text

---

### Requirement: URL-restored filters SHALL wait for account features

When opening the search page with filters embedded in the URL, the view MUST restore them only after the current account (and its feature flags) has loaded, so feature-gated filters are not stripped from the URL.

#### Scenario: advanced filters survive a page reload

- Given the account has the advanced search feature enabled
- When the user reloads a search URL containing inbox and date-range filter parameters
- Then the filters are restored and applied to the executed search

---

### Requirement: search input SHALL emit the typed value without lag

The search input MUST emit the DOM input value at event time, not a model value that updates a tick later.

#### Scenario: last character is included in the search

- Given the user types "hello" quickly
- When the debounced search fires
- Then the query is "hello", not "hell"
