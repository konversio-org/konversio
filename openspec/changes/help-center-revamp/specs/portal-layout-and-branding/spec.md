## Capability: portal-layout-and-branding

Per-portal choice between the classic and documentation public layouts, per-locale branding overrides (portal name, page title, header text), social profile links, and per-locale popular-content curation on the portal home page. Ported from upstream Chatwoot v4.14.1/v4.14.2/v4.15.0/v4.16.0 (MIT).

---

## ADDED Requirements

### Requirement: portal layout selection

Each portal SHALL store a `layout` value in `config.layout`, restricted to `classic` or `documentation`, defaulting to `classic` when unset or blank. Unknown stored values MUST NOT cause errors; public rendering falls back to `classic`.

#### Scenario: layout defaults to classic

- Given a portal with no `layout` key in `config`
- When `portal.layout` is read
- Then the result is `"classic"`

#### Scenario: layout can be switched via the API

- Given an existing portal
- When the portal is updated with `config: { layout: "documentation" }`
- Then `portal.layout` equals `"documentation"`

#### Scenario: invalid layout value is rejected

- Given an existing portal
- When the portal is updated with `config: { layout: "magazine" }`
- Then the portal fails validation with an error on `config`

#### Scenario: unknown stored layout renders as classic

- Given a portal whose stored `config.layout` is a value outside the allowed list (e.g. set by a future version)
- When a public portal page is rendered
- Then the classic layout templates are used

---

### Requirement: documentation layout rendering

Public portal pages (home, category, article, search) SHALL render a documentation-style variant — sidebar navigation with table of contents, topbar, and dedicated hero/footer — when the portal layout is `documentation`. The variant MUST be selected per request via the Rails view variant mechanism (`request.variant`), and plain-layout embeds (`show_plain_layout`) MUST continue to take precedence over the documentation variant.

#### Scenario: documentation portal home renders the documentation variant

- Given a portal with layout `documentation`
- When a visitor requests `GET /hc/:slug/:locale`
- Then the response uses the `+documentation` template variant with sidebar navigation

#### Scenario: classic portal is unaffected

- Given a portal with layout `classic`
- When a visitor requests any public portal page
- Then the response uses the default (non-variant) templates

#### Scenario: plain layout overrides documentation variant

- Given a portal with layout `documentation`
- When a page is requested with the plain-layout parameter
- Then the `+plain` variant is rendered, not the documentation variant

---

### Requirement: per-locale portal branding overrides

A portal SHALL accept per-locale overrides of `name`, `page_title`, and `header_text` under `config.locale_translations`, keyed by locale code, for any locale in the portal's `allowed_locales`. Resolution MUST fall back in order: the requested locale's override → the default locale's override → the base column value. Public pages MUST render the localized values for the active locale.

#### Scenario: locale override is used on public pages

- Given a portal with base `name` "Help" and `config.locale_translations` of `{ "fr": { "name": "Aide" } }`
- When a visitor requests the French portal home page
- Then the rendered page uses "Aide" as the portal name

#### Scenario: missing override falls back to default locale override then base column

- Given a portal with base `header_text` "Support", default-locale override `{ "en": { "header_text": "Help Center" } }`, and no `fr` override
- When the header text is resolved for locale `fr`
- Then the result is "Help Center"
- And resolving for a locale with no default-locale override present returns "Support"

#### Scenario: overrides reject unknown fields

- Given an existing portal
- When the portal is updated with `config: { locale_translations: { "fr": { "evil_key": "x" } } }`
- Then the portal fails validation

#### Scenario: admin can edit overrides per locale from the locale page

- Given a portal with multiple allowed locales
- When the user opens the locale's "customize content" dialog and saves a page title for that locale
- Then the portal API is called with the override under `config.locale_translations.<locale>.page_title`
- And the public page for that locale shows the new page title

---

### Requirement: social profile links

A portal SHALL store social profile handles under `config.social_profiles`, keyed by platform. The portal settings UI SHALL provide an editor where a platform's handle is stored without its URL prefix, and public portal footers SHALL render links only for platforms with a non-blank handle.

#### Scenario: saving a handle stores it without the URL prefix

- Given the portal settings layout/content page
- When the user enters a handle for a platform and saves
- Then `config.social_profiles.<platform>` contains only the handle

#### Scenario: blank handles are not rendered

- Given a portal with no social profiles configured
- When a public portal page is rendered
- Then no social links section is shown

---

### Requirement: per-locale popular content curation

A portal SHALL accept per-locale curated content under `config.popular_content`, with ordered `category_ids` (at most 3 surfaced) and `article_ids` (at most 6 surfaced). The portal home page MUST use curated categories/articles for the requested locale when present, preserving the admin-chosen order and skipping records that no longer exist; when absent, it MUST fall back to the first 3 position-ordered categories with published articles and the 6 most-viewed published articles for that locale. Curated category picks are honored even without published articles; curated article picks are limited to published articles.

#### Scenario: curated categories are shown in chosen order

- Given a portal with `config.popular_content.en.category_ids = [5, 2, 9]`
- When a visitor requests the English portal home page
- Then the recommended topics are categories 5, 2, 9 in that order

#### Scenario: extra curated ids are truncated to the limits

- Given a portal with 5 curated category ids and 10 curated article ids for a locale
- When the home page data is loaded
- Then at most 3 categories and at most 6 articles are used

#### Scenario: deleted records are skipped

- Given a portal whose curated article ids include an article that has been deleted
- When the home page is rendered
- Then the deleted article is omitted and the remaining curated articles keep their order

#### Scenario: fallback when no curation exists

- Given a portal with no `popular_content` for the requested locale
- When the home page is rendered
- Then recommended categories are the first 3 position-ordered categories that have published articles
- And featured articles are the 6 most-viewed published articles in that locale

#### Scenario: curated unpublished article is not surfaced

- Given a portal whose curated article ids include a draft article
- When the home page is rendered
- Then the draft article is not shown

---

### Requirement: config saves merge and never drop concurrently written keys

Portal `config` updates SHALL merge incoming keys onto the persisted config (never wholesale replace), and the update endpoint MUST take a database row lock on the portal during the update transaction so two concurrent saves cannot each overwrite the other's keys.

#### Scenario: partial config update preserves other keys

- Given a portal with `config.locale_translations` set
- When the portal is updated with `config: { layout: "documentation" }`
- Then `layout` is `"documentation"` and the existing `locale_translations` are still present

#### Scenario: concurrent saves both survive

- Given two concurrent portal update requests writing different config keys
- When both complete
- Then both keys are present in the persisted config
