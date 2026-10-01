## Capability: help-center-public-search

Server-rendered, paginated search results page for public help centers, scoped to the portal and the requested locale, plus reserved article slugs that keep search routes collision-free. Ported from upstream Chatwoot v4.14.2 (MIT).

---

## ADDED Requirements

### Requirement: public search results page

Each public portal SHALL expose a search results page at `GET /hc/:slug/:locale/search`. The page MUST search only published articles of that portal in the requested locale, using the existing full-text article search, and MUST paginate results at 10 per page. An empty or blank query MUST return no results (not all articles). The page MUST respect the portal's layout variant (classic, documentation, or plain) and the custom-domain access rules that apply to other public portal pages.

#### Scenario: query returns matching published articles in the locale

- Given a portal with published English articles about "refunds" and published French articles about "refunds"
- When a visitor requests `GET /hc/:slug/en/search?query=refunds`
- Then the results contain only the matching published English articles

#### Scenario: draft and archived articles are excluded

- Given a portal with a draft article matching the query
- When the search page is requested
- Then the draft article is not in the results

#### Scenario: blank query returns no results

- Given a portal
- When a visitor requests `GET /hc/:slug/en/search?query=` (or omits `query`)
- Then the results list is empty

#### Scenario: results are paginated

- Given a portal with 25 published English articles matching the query
- When a visitor requests page 1 of the search results
- Then at most 10 results are shown
- And page 2 is reachable via the `page` parameter

#### Scenario: search page uses the portal layout variant

- Given a portal with layout `documentation`
- When the search page is rendered
- Then the documentation variant of the search page is used, with the portal's sidebar/topbar chrome

#### Scenario: unknown portal or disabled feature returns 404

- Given a portal slug that does not exist, is archived, or whose account lacks the help center feature
- When the search page is requested
- Then a 404 is rendered in the portal's plain error chrome

---

### Requirement: search entry points

Public portal pages SHALL provide a search input that navigates to the portal's search results page for the active locale. The header search entry point MUST be available on both classic and documentation layouts.

#### Scenario: submitting the header search navigates to the results page

- Given a visitor on a public portal page for locale `en`
- When the visitor submits the search input with "billing"
- Then the browser navigates to `/hc/:slug/en/search?query=billing`

---

### Requirement: reserved article slugs

Article slugs that collide with help center public routes — `search`, `articles`, `categories` — MUST be rejected by validation on create and update, in every locale. The rejection MUST surface as a validation error through the article API.

#### Scenario: creating an article with a reserved slug fails

- Given an admin creates an article with slug `search`
- When the article is saved
- Then validation fails with an error on `slug`

#### Scenario: renaming an article to a reserved slug fails

- Given an existing article with a normal slug
- When the article is updated with slug `articles`
- Then the update is rejected with a 422 validation error

#### Scenario: reserved route still resolves to search, not an article

- Given no article named `search` can exist
- When a visitor requests `GET /hc/:slug/:locale/search`
- Then the search controller handles the request

---

### Requirement: raw markdown representation of articles

Each published article SHALL also be available as raw markdown at `GET /hc/:slug/articles/:article_slug.md`, served with a `text/markdown` content type. Draft and archived articles MUST return 404 on this route, and the custom-domain access rules for article pages apply.

#### Scenario: published article serves markdown

- Given a published article
- When a client requests its `.md` URL
- Then the response body is the article's raw markdown content with content type `text/markdown; charset=utf-8`

#### Scenario: unpublished article returns 404

- Given a draft article
- When a client requests its `.md` URL
- Then the response status is 404
