## Capability: inline-message-images

Agents can insert images directly into the reply body on email and website channels — via clipboard paste or file picker — and drag-resize them in the editor. The sizing is persisted on the image URL and honored wherever the message is rendered.

---

## ADDED Requirements

### Requirement: inline image insertion SHALL be limited to email and website channels

The reply editor MUST offer inline image insertion only when the reply is not a private note and the conversation's effective channel is email or website. Other channels and private notes MUST NOT offer inline image paste or insertion.

#### Scenario: email conversation offers inline paste

- Given an agent is composing a reply in an email inbox
- When the agent presses Cmd/Ctrl+Shift+V with an image on the clipboard
- Then the image is uploaded and inserted inline into the reply body

#### Scenario: private note does not offer inline paste

- Given an agent is composing a private note in an email inbox
- When the agent presses Cmd/Ctrl+Shift+V with an image on the clipboard
- Then no image is inserted and normal text paste is unaffected

#### Scenario: WhatsApp conversation does not offer inline paste

- Given an agent is composing a reply in a WhatsApp inbox
- When the agent presses Cmd/Ctrl+Shift+V with an image on the clipboard
- Then no image is inserted

---

### Requirement: pasted images SHALL be uploaded through the account upload endpoint

Inline image insertion MUST upload the image file to the existing account upload endpoint (`POST /api/v1/accounts/:accountId/upload`) and insert the returned file URL as an image node in the editor. Supported image types are png, jpeg, jpg, gif, and webp; files larger than 4 MB MUST be rejected with an error alert.

#### Scenario: successful paste uploads and inserts

- Given an agent pastes a 500 KB png from the clipboard
- When the upload completes
- Then an image node referencing the uploaded URL is inserted at the appropriate position in the reply body
- And the editor scrolls the image into view and regains focus
- And a success alert is shown

#### Scenario: oversized image is rejected

- Given an agent attempts to insert a 6 MB image
- Then no upload occurs
- And an error alert states the 4 MB size limit

#### Scenario: clipboard read is denied

- Given the browser denies clipboard read access
- When the agent presses Cmd/Ctrl+Shift+V
- Then no image is inserted and no error is surfaced
- And any clipboard text still pastes normally

---

### Requirement: images SHALL be drag-resizable in the editor

Each image in the editor MUST present a resize affordance that lets the agent drag to a pixel width (minimum 100px). Committing a resize MUST update the image's width attribute in the document.

#### Scenario: drag-resize persists width in markdown

- Given an agent resizes an inline image to 320px wide
- When the reply is serialized to markdown for sending
- Then the image URL carries a `cw_image_width=320px` query parameter

---

### Requirement: image sizing parameters SHALL render as inline styles

`MessageFormatter` MUST translate a `cw_image_width=<N>px` URL parameter into `style="width: <N>px; max-width: 100%; height: auto;"` on the rendered `<img>`. Width takes precedence; when no width parameter is present, a legacy `cw_image_height=<N>px` parameter MUST render as `style="height: <N>px;"`.

#### Scenario: width parameter renders sized image

- Given message content contains `![screenshot](https://example.com/a.png?cw_image_width=320px)`
- When the message is rendered in a conversation
- Then the image renders 320px wide, capped at the bubble width, with automatic height

#### Scenario: legacy height parameter still renders

- Given message content contains `![sig](https://example.com/b.png?cw_image_height=80px)`
- When the message is rendered
- Then the image renders at 80px height

---

### Requirement: message-signature image upload SHALL keep working

The message signature editor context MUST continue to support image upload through the same insertion path, keeping its distinct success and error alert copy.

#### Scenario: signature image upload shows signature copy

- Given an agent uploads an image in profile message-signature settings
- When the upload completes
- Then the success alert uses the message-signature copy, not the reply-box copy

---

### Requirement: plain-text contexts SHALL be able to suppress image rendering

`MessageFormatter` MUST expose a method that disables image rendering entirely (no `<img>` output and no image sizing), for consumers that render message content as plain text.

#### Scenario: images omitted after disabling

- Given a formatter instance on which image rendering has been disabled
- When content containing a markdown image is formatted
- Then the output contains no image markup and no image sizing styles
