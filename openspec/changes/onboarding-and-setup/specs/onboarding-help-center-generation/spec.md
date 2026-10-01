## Capability: onboarding-help-center-generation

Automatic bootstrap of a branded Help Center portal when onboarding completes with a known website, followed by a Pilot LLM pipeline that discovers help content on the site, plans categories and articles, and writes draft articles from the scraped source pages — with a polled generation-status API and UI.

**Clean-room notice:** this is a requirements-level re-expression of an upstream Enterprise feature. The upstream implementation was consulted for understanding only; all wording, service design, state naming, and copy here are original. The implementation targets Konversio's architecture: `Pilot::` LLM task services in the core tree (following the existing `Pilot::BaseTaskService` pattern in `lib/pilot/`), `app/jobs/pilot/` background jobs, no `enterprise/` paths, and no new database tables (generation state lives in the ephemeral key-value store; the generation pointer lives in `account.custom_attributes`).

needs investigation: which web scraping provider(s) Konversio will officially support for URL discovery and page scraping (self-hosted-friendly options, installation configuration keys, and the endpoint contract) — upstream uses an EE-licensed vendor client that Konversio does not have.

needs investigation: the exact discovery bound (upstream caps candidate URLs at 500) and the per-run LLM token budget — values to be settled against Pilot's configured models at implementation time.

---

## ADDED Requirements

### Requirement: branded portal bootstrap

When the account-details step of onboarding completes and a website is known for the account, the system SHALL create one Help Center portal for the account, or reuse the account's first existing portal. The created portal SHALL derive its presentation from the enriched brand data: name from the brand title or account name, color from the first brand color that is a valid 6-digit hex value (otherwise a default), header text from the brand tagline or description, homepage link from the known website with an `https://` scheme added when missing, and a unique slug. The portal's default locale SHALL be the account locale, and the portal SHALL be linked to the account's web widget channel when one exists.

#### Scenario: portal is created from brand data

- Given an account with brand data containing a title, a valid brand color, and a tagline, and no existing portal
- When onboarding completes the account-details step with a known website
- Then one portal is created with the brand title as its name and page title
- And the portal color is the brand color
- And the portal's default locale equals the account locale
- And the portal is linked to the account's web widget channel

#### Scenario: invalid brand color falls back to default

- Given the first brand color is not a valid 6-digit hex value
- When the portal is created
- Then the default portal color is used

#### Scenario: slug collisions are resolved

- Given another account's portal already uses the natural slug for this account's name
- When the portal is created
- Then an alternative unique slug is chosen, with a random suffix as the final fallback

#### Scenario: existing portal is reused

- Given the account already has a portal
- When onboarding completes
- Then no additional portal is created
- And no generation is started for the reused portal unless it is the account's first portal and generation was enqueued for it

#### Scenario: brand logo is attached defensively

- Given brand data includes a logo URL
- When the portal is created
- Then the logo is downloaded through the SSRF-safe fetch layer, restricted to image content types and a bounded size of at most 5 MB
- And a logo download failure never fails portal creation

### Requirement: generation kickoff and pointer

Portal creation during onboarding SHALL start asynchronous content generation only when a homepage link is known, and SHALL record a unique generation identifier on the account so the status API can resolve it. The pointer SHALL be cleared when onboarding finishes.

#### Scenario: generation starts with a known website

- Given the portal was created with a homepage link
- When portal creation completes
- Then a generation identifier (UUID) is stored in `account.custom_attributes`
- And a planning job is enqueued for the account, portal, completing user, and generation id

#### Scenario: no website means no generation

- Given no website or brand domain is known for the account
- When onboarding completes
- Then no generation identifier is stored
- And the status API reports generation as not started

#### Scenario: finishing onboarding clears the pointer

- Given a generation identifier is stored on the account
- When the inbox-setup step completes
- Then the generation identifier is removed from `account.custom_attributes`

### Requirement: content planning

The planning step SHALL, in order: verify that a web scraping provider and a Pilot LLM are configured for the installation (otherwise terminate as skipped); discover candidate help-content URLs on the account's website up to a bounded count (otherwise terminate as skipped when none are found); ask the LLM to propose a set of categories and a set of planned articles, each article referencing one category and one or more of the discovered URLs; persist the categories on the portal; and keep only planned articles whose category was persisted and whose source URLs all came from discovery. When fewer than a minimum threshold of 3 usable articles remains, the step SHALL terminate as skipped.

#### Scenario: plan is persisted and writer jobs are enqueued

- Given discovery returns candidate URLs and the LLM proposes 3 categories and 6 articles
- When planning completes
- Then the proposed categories exist on the portal in the portal's default locale with unique slugs and sequential positions
- And only articles whose source URLs all appeared in the discovery set are retained
- And one writer job is enqueued per retained article
- And the generation state records the retained article count as its total

#### Scenario: articles referencing unknown categories or URLs are dropped

- Given the LLM proposes an article referencing a category it did not define and an article citing a URL that was not discovered
- When planning filters the plan
- Then both articles are excluded from the retained set

#### Scenario: below-threshold plan skips terminally

- Given filtering leaves fewer than 3 articles
- When planning finishes
- Then the generation reaches a terminal skipped state
- And no writer jobs are enqueued

#### Scenario: missing provider or LLM configuration skips gracefully

- Given no scraping provider is configured, or Pilot has no usable LLM configuration
- When planning runs
- Then the generation reaches a terminal skipped state
- And onboarding can still be completed normally

### Requirement: article writing

Each writer job SHALL scrape the article's source pages, discard pages that did not return a successful (2xx) status or produced no usable text, ask the LLM to compose a title, short description, and body from the usable pages, and create the article as a **draft** attributed to the onboarding administrator, in the planned category, recording the source page URLs in the article's `meta`. A writer job whose scrape or LLM step fails MUST NOT create an article and MUST NOT block the remaining writer jobs.

#### Scenario: draft article is created with provenance

- Given a writer job for an article with two source URLs
- When both pages scrape successfully and the LLM returns composed content
- Then a draft article is created on the portal in the planned category
- And its author is the onboarding administrator
- And `meta.source_urls` lists the scraped page URLs

#### Scenario: unusable scrape fails the article only

- Given all of an article's source pages fail to scrape or return no usable text
- When the writer job runs
- Then no article is created for it
- And the job completes without raising into the retry backend
- And other writer jobs for the same generation are unaffected

#### Scenario: empty LLM output fails the article only

- Given the LLM returns a blank title or blank body
- When the writer job runs
- Then no article is created
- And the generation still advances toward its terminal state

### Requirement: durable generation state

Generation progress SHALL be tracked in the ephemeral key-value store under the generation id with a time-to-live, recording a status, the planned total, and the number of finished writer jobs. The status SHALL begin as in-progress, SHALL become completed when the finished count reaches the total, and SHALL become skipped (with a machine-readable reason) on any terminal failure. Every failure path in planning and writing — including exhausted retries and unexpected exceptions — MUST drive the state to a terminal value so the UI never waits indefinitely. A job that runs for a generation id with no recorded state SHALL do nothing (this guards retried planning jobs after a terminal state was recorded).

#### Scenario: completed when all writers finish

- Given a generation with a total of 5 articles
- When the fifth writer job finishes (successfully or not)
- Then the generation status is completed

#### Scenario: writer failure still counts toward completion

- Given a generation with a total of 5 articles
- When a writer job fails permanently
- Then the finished count still advances
- And the generation completes once all 5 writer jobs have finished

#### Scenario: state expires

- Given a generation finished more than the TTL ago
- When the status API is queried
- Then no state is returned for that generation id

#### Scenario: replayed planning job is inert after a terminal state

- Given a planning job that exhausted retries and recorded a skipped state
- When the same planning job runs again
- Then it exits without re-planning or enqueuing writers

### Requirement: generation status API

The system SHALL expose `GET /api/v1/accounts/:account_id/onboarding/help_center_generation` to account administrators, returning `generation_id`, `state`, `articles_count`, and `categories_count`. When no generation pointer is stored, all fields SHALL be nil/zero. When a pointer exists, `state` SHALL be the tracked generation state, and the counts SHALL reflect the account's first portal.

#### Scenario: status during generation

- Given a generation in progress with 2 of 5 articles written
- When the status endpoint is queried
- Then the response contains the generation id and the in-progress state
- And `articles_count` is 2

#### Scenario: status with no generation

- Given the account has no stored generation pointer
- When the status endpoint is queried
- Then the response is `{ generation_id: nil, state: nil, articles_count: 0, categories_count: 0 }`

### Requirement: generation status UI

During the inbox-setup step the dashboard SHALL display a Help Center creation status row that polls the status API at a bounded interval (about every 5 seconds, without overlapping requests) until the generation reaches a terminal state. While generating, the row SHALL show live progress (articles written so far, rotating phase messaging before the first article); on completion it SHALL show the final article and category counts; when generation never started or was skipped, the row SHALL NOT be displayed. Transient poll failures SHALL NOT stop polling or block onboarding completion.

#### Scenario: polling stops at a terminal state

- Given the status row is polling during generation
- When the API reports completed or skipped
- Then polling stops
- And on completed, the row shows the final counts

#### Scenario: hidden when skipped or not started

- Given the API reports no generation or a skipped generation
- When the inbox-setup step renders
- Then no Help Center status row is shown

#### Scenario: onboarding can finish while generation runs

- Given generation is still in progress
- When the user completes or skips the inbox-setup step
- Then onboarding finishes normally
- And the generation continues in the background
