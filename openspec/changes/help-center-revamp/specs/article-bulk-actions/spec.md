## Capability: article-bulk-actions

Bulk operations on help center articles from the admin UI: change status, move to another category, and delete — for an arbitrary selection of articles, atomically. Ported from upstream Chatwoot v4.14.0/v4.14.1 (MIT). Upstream's bulk AI translation action is Enterprise-only and is stubbed (`501`) pending a separate Pilot-based change.

---

## ADDED Requirements

### Requirement: bulk actions endpoints

The admin API SHALL expose bulk article actions nested under a portal: `POST /api/v1/accounts/:account_id/portals/:portal_slug/articles/bulk_actions/translate`, `PATCH .../bulk_actions/update_status`, `PATCH .../bulk_actions/update_category`, and `DELETE .../bulk_actions/delete_articles`. All actions take `ids` (article ids) and operate only on articles belonging to that portal. All actions MUST require article-management authorization. Empty selections (no matching articles) MUST return 422 with an explanatory error.

#### Scenario: update_status changes all selected articles atomically

- Given a portal with articles 1, 2, 3 in draft status
- When the API receives `update_status` with `ids: [1, 2, 3]` and `status: "published"`
- Then all three articles are published
- And the response is 200

#### Scenario: invalid status is rejected

- Given selected articles exist
- When `update_status` is called with `status: "banana"`
- Then the response is 422
- And no article's status changed

#### Scenario: failed update rolls back the whole batch

- Given selected articles where one fails validation on update
- When `update_status` runs
- Then the response is 422 with the validation message
- And none of the selected articles were modified

#### Scenario: update_category moves articles to a category in the same portal

- Given a portal with category "Guides" and articles in "FAQ"
- When `update_category` is called with those articles' ids and the "Guides" category id
- Then all selected articles belong to "Guides"

#### Scenario: category from another portal is rejected

- Given a category that belongs to a different portal
- When `update_category` targets it
- Then the response is 422
- And no article moved

#### Scenario: delete_articles destroys the selection

- Given selected articles
- When `delete_articles` is called with their ids
- Then those articles no longer exist

#### Scenario: empty selection returns 422

- Given `ids` that match no articles of the portal
- When any of the bulk actions is called
- Then the response is 422 with a "no articles found" error

#### Scenario: ids from another portal are not touched

- Given an article belonging to a different portal of the same account
- When a bulk action includes that article's id
- Then that article is not part of the operated set (the portal scope excludes it)

#### Scenario: unauthorized user is rejected

- Given a user without article-management permission
- When they call any bulk action
- Then the response is an authorization failure (403 or equivalent)

#### Scenario: translate action is not implemented

- Given selected articles
- When `translate` is called
- Then the response is 501 Not Implemented

---

### Requirement: bulk selection UI on the articles page

The help center articles page SHALL allow selecting individual articles and selecting all articles in the current view (including across pages). When the selection is non-empty, a bulk action bar SHALL offer: change status (publish / draft / archive), change category, delete (with confirmation), and a clear-selection control. Status changes that target an article's current status MUST be skipped client-side. The UI MUST update optimistically and roll back with an error alert on API failure.

#### Scenario: selecting articles shows the bulk bar

- Given the articles list for a portal
- When the user checks two articles
- Then a bulk action bar appears showing "2 selected" with status, category, and delete actions

#### Scenario: bulk publish updates the list optimistically

- Given two selected draft articles
- When the user chooses publish from the bulk bar
- Then both articles immediately show as published in the list
- And the `update_status` API is called with both ids and `status: "published"`

#### Scenario: failed bulk action rolls back the optimistic update

- Given the `update_status` API call fails
- When the user chose publish
- Then the articles revert to draft in the list
- And an error alert is shown

#### Scenario: bulk change category uses the category picker

- Given a selection of articles
- When the user picks a target category in the bulk bar
- Then the `update_category` API is called with the selected ids and category id
- And the list reflects the new category

#### Scenario: bulk delete asks for confirmation

- Given a selection of articles
- When the user chooses delete
- Then a confirmation dialog is shown
- And confirming calls the delete endpoint and removes the articles from the list

#### Scenario: clearing the selection hides the bar

- Given an active selection
- When the user clears it
- Then the bulk action bar disappears and no article is selected
