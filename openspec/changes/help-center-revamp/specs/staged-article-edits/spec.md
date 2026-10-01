## Capability: staged-article-edits

Edits to a published article are staged in `draft_title` / `draft_content` instead of going live immediately. The public site keeps serving the last published version until the author explicitly publishes the staged changes (or discards them). Ported from upstream Chatwoot v4.16.0 (MIT).

---

## ADDED Requirements

### Requirement: draft columns on articles

Articles SHALL have nullable `draft_title` (string) and `draft_content` (text) columns, exposed in the admin article API payloads as `draft_title` and `draft_content`, and permitted in the article update endpoint.

#### Scenario: new articles have no staged draft

- Given a newly created article
- Then `draft_title` and `draft_content` are null

#### Scenario: drafts are exposed in the API

- Given an article with staged edits
- When the article is fetched via the admin API
- Then the payload includes `draft_title` and `draft_content`

---

### Requirement: autosave on published articles stages instead of publishing

When the article editor autosaves title or content on a **published** article, the API MUST write only `draft_title` / `draft_content`, leaving `title`, `content`, and the public-facing `updated_at` untouched. Draft-only writes MUST still run model validations before persisting (so over-length content cannot be stored), but MUST NOT bump `updated_at`.

#### Scenario: autosave stages content without touching the live record

- Given a published article with title "Old" and content "Live body"
- When the editor autosaves title "New" and content "Edited body"
- Then the article's `title` remains "Old" and `content` remains "Live body"
- And `draft_title` is "New" and `draft_content` is "Edited body"
- And `updated_at` is unchanged

#### Scenario: public site serves the live version while a draft is staged

- Given a published article with staged edits
- When a visitor requests the article's public page
- Then the published title and content are rendered, not the staged draft

#### Scenario: invalid staged content is not persisted

- Given a published article
- When a draft-only autosave carries content that fails validation (e.g. exceeds the column limit)
- Then the staged columns are not updated
- And the API responds with a validation error

#### Scenario: non-published articles save directly and absorb leftover drafts

- Given a draft-status article that has leftover `draft_title`/`draft_content` values (e.g. it was moved back from published via the card or bulk menu)
- When the editor autosaves a title change
- Then the save writes `title`/`content` on the live record, promoting the other staged field's value so nothing is lost
- And `draft_title` and `draft_content` are cleared to null

---

### Requirement: pending-changes state and diff preview

The admin UI SHALL indicate articles with staged edits: an "unpublished changes" state on the article card and editor header, plus a diff view comparing the staged draft against the live version (title compared word-by-word; body compared block-by-block). A staged draft that renders identically to the live version (whitespace-only markdown differences) MUST be treated as no change and cleared automatically on save.

#### Scenario: staged edits show a pending-changes badge

- Given a published article with staged edits
- When the articles list is rendered
- Then the article card shows an "unpublished changes" indicator

#### Scenario: reverting edits to the live content clears the draft

- Given a published article with staged edits
- When the author edits title and body back to values equal to the live version and autosave runs
- Then `draft_title` and `draft_content` become null
- And the pending-changes indicator disappears

#### Scenario: whitespace-only body edit clears the draft

- Given a published article whose staged body differs from the live body only by blank lines
- When autosave runs
- Then the staged draft is cleared (the CommonMark renders are identical)

#### Scenario: diff view highlights additions and removals

- Given a published article with staged edits
- When the author opens the pending-changes diff view
- Then removed live content and added draft content are visually distinguished

---

### Requirement: resolving a staged draft

Changing the status of a published article that has staged edits (publish from the editor, or draft/archive from the card menu) MUST first ask the author to apply or discard the staged changes. Applying promotes `draft_title` → `title` and `draft_content` → `content` in the same update that changes status, then nulls the draft columns. Discarding nulls the draft columns and keeps the live content. Resolution MUST be blocked while an autosave or file upload is in flight.

#### Scenario: publish with staged edits promotes the draft

- Given a published article with staged title "New" and body "Edited"
- When the author chooses to apply the changes and publish
- Then `title` is "New", `content` is "Edited", both draft columns are null
- And the public page now serves the new content

#### Scenario: discard keeps the live content

- Given a published article with staged edits
- When the author chooses discard
- Then both draft columns are null
- And `title`/`content` are unchanged

#### Scenario: status change without staged edits needs no prompt

- Given a published article with no staged edits
- When the author moves it to draft
- Then no apply/discard prompt is shown
- And the status changes directly

#### Scenario: resolution is blocked during in-flight autosave

- Given an autosave request is in flight
- When the author tries to apply or discard the staged draft
- Then the action is blocked until the autosave completes

---

### Requirement: author assignment validation

The article create endpoint MUST reject an `author_id` that is not a user of the current account (422). The update endpoint MUST silently drop an invalid `author_id` and apply the remaining changes, so transfers/deactivated accounts cannot block edits.

#### Scenario: create with foreign author id fails

- Given a user id belonging to a different account
- When an article is created with that `author_id`
- Then the response is 422 and no article is created

#### Scenario: update with foreign author id ignores the author change

- Given an existing article
- When it is updated with a foreign `author_id` plus a new description
- Then the description is saved
- And the article's author is unchanged
