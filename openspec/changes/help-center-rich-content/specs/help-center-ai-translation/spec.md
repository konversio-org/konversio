## Capability: help-center-ai-translation

Bulk AI translation of Help Center articles into a portal's other allowed locales, powered by Pilot. Translations are created as drafts linked to the source article so humans review before publishing.

Clean-room note: this capability originated in upstream's Enterprise edition. These requirements describe observable behavior and API contracts in original wording; no upstream prompt text, copy, or implementation structure is reproduced. Implementation lives in the core tree under the `Pilot::` namespace.

---

## ADDED Requirements

### Requirement: bulk translate endpoint

The system SHALL expose `POST /api/v1/accounts/:account_id/portals/:portal_id/articles/bulk_actions/translate` accepting `ids` (array of article ids), `locale` (target locale code), optional `category_id` (target category), and optional `force` (boolean). Access MUST require article-create authorization on the portal.

#### Scenario: happy path enqueues one job per article

- Given a portal with allowed locales `en` and `nl`
- And two published articles in locale `en` with no `nl` translations
- When an authorized user POSTs `{ ids: [a1, a2], locale: "nl" }` to the translate endpoint
- Then the response is `200 OK`
- And one `Pilot::Articles::TranslateJob` is enqueued per article with the article id, target locale, and requesting user

#### Scenario: Pilot tasks feature disabled

- Given the account does not have Pilot task features enabled
- When an authorized user POSTs a translate request
- Then the response is an error status with a message indicating translation is unavailable
- And no jobs are enqueued

#### Scenario: target locale must be allowed on the portal

- Given a portal whose allowed locales do not include `fr`
- When the user POSTs a translate request with `locale: "fr"`
- Then the request is rejected with an error status
- And no jobs are enqueued

#### Scenario: target category must exist in the target locale

- Given a portal with allowed locale `nl`
- And a category that exists only in locale `en`
- When the user POSTs a translate request with `locale: "nl"` and that category's id
- Then the request is rejected with an error status
- And no jobs are enqueued

#### Scenario: empty article selection

- Given a translate request whose `ids` match no articles in the portal
- When the request is submitted
- Then the request is rejected with an error status
- And no jobs are enqueued

---

### Requirement: duplicate translation detection

Before enqueueing, the system MUST detect articles in the target locale already linked (via the shared root article) to any selected article. If duplicates exist and the request does not set `force`, the system SHALL respond `409 Conflict` with the conflicting articles' ids and titles. If `force` is set, the system SHALL proceed, and the translation job MUST update the existing translation rather than create a new article.

#### Scenario: duplicates block translation without force

- Given article A in locale `en` already has a translation A' in locale `nl`
- When the user POSTs `{ ids: [A], locale: "nl" }` without `force`
- Then the response is `409 Conflict`
- And the response body lists A' (id and title) as a duplicate
- And no job is enqueued for A

#### Scenario: force overwrites existing translations

- Given article A in locale `en` already has a translation A' in locale `nl`
- When the user POSTs `{ ids: [A], locale: "nl", force: true }`
- Then the response is `200 OK`
- And when the job runs, A' is updated in place (not duplicated)

---

### Requirement: translation job creates linked drafts

`Pilot::Articles::TranslateJob` SHALL translate the source article's title and content into the target locale's language and persist the result as an article in the target locale linked to the source's root article (`associated_article_id`), with status `draft` and the requesting user as author. When a `category_id` is provided, the new article MUST be assigned to that category. When a linked translation already exists in the target locale, the job MUST update that article's title and content (and refresh the description from the source) instead of creating a duplicate.

#### Scenario: new translation is a linked draft

- Given a published article "Getting started" in locale `en`, category "Basics"
- When the translate job runs for target locale `nl`, target category "Basis", user U
- Then a new article exists in locale `nl`, category "Basis"
- And its status is `draft`
- And its author is U
- And its `associated_article_id` equals the source article's root id

#### Scenario: re-running updates the existing translation

- Given the draft translation from the previous scenario
- When the translate job runs again for the same source article and locale
- Then no additional article is created
- And the existing translation's title and content reflect the latest source text

#### Scenario: blank content is not sent to the LLM

- Given a source article whose content is blank
- When the translate job runs
- Then only the title is translated
- And the new article's content remains blank

---

### Requirement: translation service preserves article structure

The translation LLM service (`Pilot` task service) SHALL accept a text, a target language name, and a type (`title` or `content`); any other type MUST raise an argument error. For `content`, the LLM instructions SHALL require: translate only human-visible text; preserve all markdown constructs (headings, emphasis, links, lists, tables, code blocks, blockquotes), all HTML tags and attributes, all URLs, image references, iframes and embedded media, and the original line-break/whitespace layout; return only the translated text. For `title`, the instructions SHALL require returning only the translated title. The target language name MUST be resolved from the installation's locale-to-language map, falling back to the raw locale code when unmapped.

#### Scenario: invalid type is rejected

- Given the translation service
- When it is invoked with type `:summary`
- Then an argument error is raised

#### Scenario: markdown and media survive translation

- Given an article body containing a heading, a table, an image, a code block, and a video embed URL
- When the body is translated to another language
- Then headings, table structure, the image reference, the code block, and the embed URL are unchanged
- And only the human-readable text is translated

#### Scenario: unmapped locale falls back to the locale code

- Given a locale code absent from the language map
- When the service resolves the target language
- Then the locale code itself is used as the target language label

---

### Requirement: bulk translate dialog in the article list

The article list UI SHALL offer a translate action for selected articles when Pilot task features are enabled. The dialog MUST let the user pick a target locale (excluding the article list's current locale), optionally pick a target category from that locale's categories, and confirm. When the API reports duplicates, the dialog MUST list the conflicting articles (with links to edit them) and require an explicit overwrite confirmation before retrying with `force`.

#### Scenario: action hidden without Pilot tasks

- Given an account without Pilot task features enabled
- When the user selects articles in the list
- Then no translate action is offered

#### Scenario: successful start

- Given two selected articles and a chosen target locale `nl`
- When the user confirms the dialog
- Then the translate request is submitted and the dialog reports that translation has started

#### Scenario: duplicate conflict requires overwrite confirmation

- Given the API responds `409` with one conflicting article
- When the dialog receives the response
- Then it displays the conflicting article with a link to open it
- And the confirm action is relabeled to an explicit overwrite action
- And confirming again submits the request with `force: true`
