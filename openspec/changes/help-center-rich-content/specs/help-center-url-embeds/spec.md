## Capability: help-center-url-embeds

Authors can insert supported URL embeds (YouTube, Loom, Vimeo, MP4, Arcade, Wistia, Bunny, CodePen, GuideJar, GitHub Gist, and any future entry in `config/markdown_embeds.yml`) into Help Center articles via a slash-menu command, see live previews in the editor, and readers see the rendered embed on public portal pages. The YAML config is the single source of truth for both editor preview and server-side rendering.

MIT port: the editor helper, popover component, plugin usage, and renderer behavior reference upstream core-tree files directly (`app/javascript/dashboard/helper/markdownEmbeds.js`, `VideoEmbedInput.vue`, `lib/custom_markdown_renderer.rb`).

---

## ADDED Requirements

### Requirement: shared embed configuration drives editor and renderer

Both the article editor and the public article renderer SHALL derive supported embed types from `config/markdown_embeds.yml`. Each entry defines a URL-matching pattern with named captures and an HTML template. Adding a new embed type to the YAML MUST make it available to the editor preview and the public renderer without code changes. Embed types that cannot render inline in the editor (e.g. script-injection embeds such as GitHub Gist) MAY be excluded from the editor preview while still rendering on public pages.

#### Scenario: new embed type needs no code change

- Given a new entry is added to `config/markdown_embeds.yml` with a regex and template
- When the editor and public renderer load
- Then URLs matching the new pattern preview in the editor and render as embeds on public pages

#### Scenario: non-previewable embeds still render publicly

- Given an article containing a bare GitHub Gist link
- When the article is viewed on the public portal
- Then the gist embed markup is rendered
- And the editor may show the plain link instead of a live preview

---

### Requirement: slash-menu video embed command

The article editor's slash menu SHALL include a "Video" command that opens an embed popover anchored at the caret. The popover MUST accept a URL, validate it against every configured embed pattern, show an error state for unsupported URLs, and on submit insert the URL as a bare linked paragraph (the form the public renderer upgrades to an embed). The popover SHALL also offer uploading a local MP4 file (see `help-center-media-uploads`).

#### Scenario: valid embed URL is inserted

- Given the author opens the Video command and pastes a supported YouTube URL
- When the author submits
- Then a paragraph containing the bare linked URL is inserted at the caret
- And a live embed preview replaces the link in the editor

#### Scenario: unsupported URL shows an error

- Given the author pastes `https://example.com/video`
- When the author submits
- Then nothing is inserted
- And an unsupported-link error is shown in the popover

#### Scenario: popover cancellation restores focus

- Given the embed popover is open
- When the author cancels (Escape or cancel action)
- Then the popover closes and editor focus is restored

---

### Requirement: live embed previews in the editor

The editor SHALL render a live preview (iframe/video/player per the config template) in place of any isolated bare link that matches a configured embed pattern. Previews MUST reflect the current document content: editing or deleting the link updates or removes the preview. Embed types flagged `hide_source` (editor-only embeds such as direct MP4 links) SHALL replace the raw link line in the editor preview while the underlying content remains the bare link.

#### Scenario: typing a bare embed link shows a preview

- Given the author types a YouTube URL on its own line
- When the URL is recognized
- Then the editor displays the YouTube player preview in place of the raw link

#### Scenario: removing the link removes the preview

- Given an embed preview is shown
- When the author deletes the link
- Then the preview disappears

---

### Requirement: public renderer safety and fidelity

The public article renderer SHALL substitute named captures into embed templates only after HTML-escaping each captured value, MUST render embeds only for isolated bare links (not inline links within a sentence), and SHALL honor a saved display width carried on the link (a `cw_video_width=<N>px` query parameter) by constraining the rendered embed to that width while keeping it responsive.

#### Scenario: crafted URL cannot inject markup

- Given a link URL that matches an embed pattern but whose captured value contains quote or angle-bracket characters
- When the article is rendered publicly
- Then the captured value is HTML-escaped in the output
- And no attribute breakout or injected element occurs

#### Scenario: inline links are not upgraded

- Given the sentence "Watch [this](https://youtube.com/watch?v=xyz) tutorial" (link inline in a paragraph)
- When the article is rendered publicly
- Then the link renders as a normal hyperlink, not an embed

#### Scenario: saved width constrains the embed

- Given an embed link carrying `?cw_video_width=480px`
- When the article is rendered publicly
- Then the embed output is constrained to 480px wide with responsive fallback (max-width 100%)
