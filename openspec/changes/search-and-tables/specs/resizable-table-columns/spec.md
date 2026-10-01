## Capability: resizable-table-columns

Help Center article authors can drag table column borders to set pixel widths in the article editor; widths persist through the markdown round-trip via an internal comment marker, are re-applied when the editor reloads, render fixed-width on the public portal, and never leak as visible text.

---

## ADDED Requirements

### Requirement: article table columns SHALL be drag-resizable

The article editor MUST enable drag-resizing of table columns with a minimum cell width of 50px, and MUST provide table controls to add and remove rows and columns.

#### Scenario: author resizes a column

- Given an article containing a table
- When the author drags a column border to widen the column
- Then the column renders at the dragged width in the editor
- And no column can be dragged below 50px

---

### Requirement: column widths SHALL persist in the article markdown

When an article is saved, each table with explicitly sized columns MUST be preceded in the serialized markdown by an internal comment marker `<!--cw-colwidths:w1,w2,...-->` listing the first-row column widths in pixels, with 0 for unset columns. Tables with no sized columns MUST NOT emit a marker. When the editor loads an article, marker widths MUST be re-applied to the corresponding table's columns.

#### Scenario: widths survive save and reload

- Given an author resized a table's columns to 200px and 120px
- When the article is saved and the editor is reloaded
- Then the table renders with 200px and 120px columns

#### Scenario: unsized table emits no marker

- Given a table whose columns were never resized
- When the article is saved
- Then the markdown contains no column-width marker for that table

---

### Requirement: the marker SHALL never surface as visible text

`MessageFormatter` MUST strip column-width marker lines — including any blockquote `>` prefixes — from content before rendering or producing plain text, so the marker never appears in dashboard conversations, search snippets, or any other formatted output.

#### Scenario: marker stripped from rendered output

- Given content containing `<!--cw-colwidths:200,120-->` followed by a table
- When the content is rendered or converted to plain text
- Then the output contains no trace of the marker text
- And the table itself still renders

#### Scenario: quoted table marker stripped without breaking parsing

- Given a blockquote containing a marker line prefixed with `>` followed by a table
- When the content is rendered
- Then the marker is removed and the quoted table still parses as a table

---

### Requirement: the public portal SHALL render marked tables with fixed column widths

The server-side article renderer MUST detect a column-width marker preceding a table and render that table with a `<colgroup>` carrying the pixel widths, `table-layout: fixed`, and a width-limited wrapper. Unset columns (0 in the marker) MUST default to the 50px editor minimum. Tables without a marker MUST render exactly as they do today (auto layout inside the existing `.tableWrapper`).

#### Scenario: marked table renders fixed widths on the portal

- Given a published article whose markdown contains `<!--cw-colwidths:200,0-->` before a two-column table
- When a visitor views the article on the public portal
- Then the table renders with the first column at 200px and the second at 50px
- And the table uses fixed layout within a wrapper capped at the content width

#### Scenario: unmarked table is unchanged

- Given a published article with a table and no marker
- When the article renders on the portal
- Then the table renders with automatic layout as before this change
