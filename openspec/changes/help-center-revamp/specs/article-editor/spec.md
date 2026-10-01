## Capability: article-editor

Help center article editor improvements: resizable table columns that persist into the public render, sized images, video embeds, and toolbar constraints inside table cells. Ported from upstream Chatwoot v4.14.2/v4.15.0 (MIT); the URL/video embed provider set comes from `config/markdown_embeds.yml` (v4.14.0 groundwork).

---

## ADDED Requirements

### Requirement: resizable table columns

The article editor SHALL allow dragging table column borders to resize columns (minimum cell width 50px). Resized widths MUST be serialized into the article markdown as a `<!--cw-colwidths:N,N,...-->` comment immediately before the table, and the public markdown renderer MUST consume that marker to emit a sized table: when every column has a positive width, the table wrapper hugs the exact total width (capped at 100%); partially sized tables stay full-width; cells without an explicit width render at the 50px minimum, matching the editor. The marker itself MUST NOT appear in the rendered output.

#### Scenario: resizing persists through save and public render

- Given an article with a table whose columns the author resized in the editor
- When the article is saved and viewed on the public portal
- Then the rendered table uses the same column widths

#### Scenario: marker is not visible in output

- Given article markdown containing a `cw-colwidths` comment before a table
- When the public renderer processes it
- Then the comment text does not appear in the HTML

#### Scenario: unresized tables render as before

- Given an article with a table and no colwidths marker
- When the article is rendered publicly
- Then the table renders with the default full-width wrapper

---

### Requirement: sized images

Images in the article editor SHALL support an explicit width, serialized into the image URL/marker and rendered publicly as a `width` style with `max-width: 100%` and automatic height.

#### Scenario: sized image renders with its width

- Given an article image with a configured width
- When the article renders publicly
- Then the `img` tag carries `style="width: <width>; max-width: 100%; height: auto;"`

#### Scenario: unsized images render without inline sizing

- Given an article image with no width configured
- When the article renders publicly
- Then no width style is emitted

---

### Requirement: video and URL embeds

The article editor SHALL support embedding videos and rich URL embeds (the provider set configured in `config/markdown_embeds.yml`: at minimum YouTube, Loom, Vimeo, and direct mp4 links). Pasted or inserted embed URLs MUST render as responsive embedded players on the public portal; mp4 links render as an HTML5 video element. Embed URL patterns and templates MUST remain data-driven via the embed config file so providers can be added without renderer code changes.

#### Scenario: YouTube URL renders as an embedded player

- Given an article containing a YouTube watch URL on its own line
- When the article renders publicly
- Then a responsive iframe embed for that video is rendered

#### Scenario: mp4 link renders as a video element

- Given an article containing a direct `.mp4` URL
- When the article renders publicly
- Then a `<video controls>` element with that source is rendered

---

### Requirement: toolbar constraints inside table cells

When the editor cursor is inside a markdown table cell, toolbar options that produce block content a table cell cannot hold — headings, lists, image upload, table insertion, horizontal rule, video — MUST be disabled, because such content would be lost on markdown serialization.

#### Scenario: block options are disabled inside a table cell

- Given the cursor inside a table cell in the article editor
- Then heading, list, image, insert-table, horizontal-rule, and video toolbar options are disabled

#### Scenario: all options available outside tables

- Given the cursor in a normal paragraph
- Then the full toolbar option set is enabled
