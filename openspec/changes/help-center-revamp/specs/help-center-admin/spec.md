## Capability: help-center-admin

Admin-side article management improvements on the help center articles page: full-text search of articles and drag-to-reorder with server-side position rebalancing. Ported from upstream Chatwoot v4.16.0 (MIT).

---

## ADDED Requirements

### Requirement: admin article search

The articles page SHALL provide a search input that filters the article list by title/content text using the existing admin articles index `query` parameter. Search input MUST be debounced (about 500 ms), in-flight requests MUST be aborted when superseded by a newer query, and the active query MUST be reflected in the page URL (`?search=`) so the view is shareable and survives navigation.

#### Scenario: typing filters the article list

- Given a portal with articles titled "Refunds" and "Shipping"
- When the user types "refund" in the search input
- Then after the debounce, the list shows only articles matching "refund"
- And the articles API was called with the `query` parameter

#### Scenario: superseded requests are aborted

- Given a search request in flight for "ref"
- When the user continues typing "refund"
- Then the "ref" request is aborted and only the "refund" request's results render

#### Scenario: query syncs to the URL

- Given the user searched for "billing"
- Then the page URL contains `?search=billing`
- And reloading the page restores the filtered view

#### Scenario: clearing the search restores the full list

- Given an active search filter
- When the user clears the input
- Then the unfiltered article list is shown

---

### Requirement: drag-to-reorder articles

Within a category's article list, authorized users SHALL be able to reorder articles by dragging. Dragging MUST be disabled while a search filter is active. The client sends a `positions_hash` (`{ article_id => position }`) to the reorder endpoint; the server MUST apply the given positions and then rebalance the affected categories in one transaction, re-spacing positions to 10-step values in a stable order (current position, then dragged articles after non-dragged, then id), and MUST return the final `{ article_id => position }` map as JSON.

#### Scenario: reorder applies new positions and rebalances the category

- Given a category with articles at positions 1, 2, 2 (a collision)
- When the reorder endpoint receives `positions_hash` moving the third article to position 1
- Then all articles in the category end up at distinct 10-step positions (10, 20, 30, ...)
- And the response body contains the final positions map

#### Scenario: same-page reorder updates without refetch

- Given all visible articles fit on one page
- When the user drags an article to a new position
- Then the list reorders immediately using the returned positions map
- And no full list refetch occurs

#### Scenario: cross-page drop refetches the list

- Given a category whose articles span multiple pages
- When the user drags an article across a page boundary
- Then the list is refetched to reflect the move

#### Scenario: reorder is disabled while searching

- Given an active search filter on the articles page
- Then drag handles are not available

#### Scenario: reorder endpoint requires a non-empty payload

- Given an authorized request
- When the reorder endpoint is called with a blank `positions_hash`
- Then it responds successfully with an empty positions map and changes nothing
