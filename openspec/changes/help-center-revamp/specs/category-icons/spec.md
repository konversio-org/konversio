## Capability: category-icons

Help center categories can carry an emoji or icon plus a color, shown in the admin category form, the article editor's category selector, category listings, and public portal pages. Ported from upstream Chatwoot v4.15.0 (MIT).

---

## ADDED Requirements

### Requirement: icon color stored on categories

Categories SHALL have a nullable `icon_color` string column. The admin categories API MUST permit `icon_color` on create/update and expose `icon` and `icon_color` in article payloads' embedded category object.

#### Scenario: icon color is persisted via the API

- Given an existing category
- When it is updated with `icon: "rocket"` and `icon_color: "blue"`
- Then both values are stored and returned by the API

#### Scenario: article payloads include category icon data

- Given an article in a category that has an icon and icon color
- When the article is fetched via the admin API
- Then the embedded `category` object includes `icon` and `icon_color`

---

### Requirement: icon picker in the category form

The category create/edit form SHALL provide an emoji/icon picker: choosing an emoji clears the color; choosing an icon allows picking a color; removing the icon clears both fields.

#### Scenario: choosing an emoji clears the color

- Given the category form with an icon and color previously set
- When the user picks an emoji as the icon
- Then `icon_color` is cleared

#### Scenario: choosing an icon keeps color selection available

- Given the category form
- When the user picks a (non-emoji) icon and a color
- Then saving sends both `icon` and `icon_color`

#### Scenario: removing the icon clears both fields

- Given a category with an icon and color
- When the user removes the icon and saves
- Then `icon` and `icon_color` are blank

---

### Requirement: icons rendered in admin and public surfaces

Category icons (with color) SHALL render in the article editor's category selector and the admin category list/cards, and on public portal category blocks in both classic and documentation layouts.

#### Scenario: article editor category selector shows icons

- Given categories with icons
- When the author opens the category selector in the article editor
- Then each category option shows its icon in its color

#### Scenario: public category blocks show icons

- Given a category with an emoji icon
- When the public portal home or category page is rendered
- Then the category block displays the emoji

#### Scenario: categories without icons render cleanly

- Given a category with no icon
- When admin and public pages render it
- Then no broken icon placeholder is shown
