## Capability: help-center-category-article-creation

Creating a Help Center article from within a category view pre-assigns the article to that category and keeps the author in the category context after save, instead of silently filing the article under the first category.

MIT port: references upstream core-tree changes to `helpcenter.routes.js` and `PortalsArticlesNewPage.vue`.

---

## ADDED Requirements

### Requirement: category-scoped new-article route

The dashboard SHALL provide a category-scoped article creation route (`:portalSlug/:locale/categories/:categorySlug/articles/new`) that resolves the target category from the route's category slug and preselects it for the new article. When the slug matches no category, the system MUST fall back to the portal's first category (current behavior).

#### Scenario: category resolved from the route

- Given the author is browsing category "Getting Started" in a portal
- When the author starts a new article from the category view
- Then the creation form opens with "Getting Started" preselected as the article's category

#### Scenario: unknown category slug falls back

- Given a category-scoped creation URL whose slug matches no category
- When the creation form opens
- Then the portal's first category is preselected

---

### Requirement: article created in the preselected category

Saving the new article MUST create it in the resolved (or author-changed) category, not in the portal's first category by default.

#### Scenario: article lands in the browsed category

- Given the author started creation from category "Getting Started"
- When the article is saved without changing the category
- Then the article's category is "Getting Started"

#### Scenario: author can override the category

- Given the author started creation from category "Getting Started"
- When the author selects category "Advanced" before saving
- Then the article's category is "Advanced"

---

### Requirement: navigation stays in category context

After a successful create from a category-scoped route, the system MUST navigate to the category-scoped edit view of the new article, preserving the category context. Back navigation from the category-scoped creation or edit view MUST return to that category's article list rather than the global article list.

#### Scenario: create redirects to category-scoped editor

- Given a new article created from category "Getting Started"
- When the create completes
- Then the browser navigates to the article's edit view within the "Getting Started" category context

#### Scenario: back returns to the category list

- Given the author is on the category-scoped creation page for "Getting Started"
- When the author navigates back
- Then the "Getting Started" category article list is shown
