## Capability: help-center-media-uploads

Article authors get robust media uploads in the Help Center editor: visible progress, previews, retry/cancel/remove on failed uploads, MP4 video support, image resizing, and guards that prevent losing uploads by publishing or navigating away too early.

MIT port: references upstream core-tree changes to `FullEditor.vue`, `uploadHelper.js`, `helpCenterArticles` store actions, and `@chatwoot/prosemirror-schema` 1.4.5 plugins.

---

## ADDED Requirements

### Requirement: upload progress and lifecycle in the editor

Inserting an image or video (via file picker, drag-drop, or paste) SHALL display an in-document upload indicator showing progress from 0 to 100%. A failed upload MUST remain visible as an error card offering retry, remove, and (while in flight) cancel. Cancelling MUST abort the underlying HTTP request. Labels (uploading, failed, rate-limited, retry, remove, cancel) MUST come from i18n.

#### Scenario: progress is visible during upload

- Given the author drops a 3 MB image into the editor
- When the upload begins
- Then an upload indicator appears at the insertion point showing live progress
- And on completion the indicator is replaced by the image

#### Scenario: failed upload offers retry and remove

- Given an upload fails (network error or server rejection)
- Then an error card remains in the document
- And the author can retry the upload or remove the card

#### Scenario: cancel aborts the request

- Given an upload in flight
- When the author cancels it
- Then the HTTP request is aborted and the indicator is removed

---

### Requirement: unified file type and size gating

Every upload entry point (file picker, drop, paste) MUST pass the same gate: images (PNG, JPEG, GIF, WebP) up to 4 MB, and `video/mp4` up to the account's configured maximum file upload size. Files failing the gate MUST produce a descriptive alert and never start an upload.

#### Scenario: oversized image is rejected with an alert

- Given the author selects a 6 MB PNG
- Then an alert states the image size limit
- And no upload starts

#### Scenario: MP4 within the account limit uploads as video

- Given the account maximum upload size is 40 MB and the author selects a 20 MB MP4
- Then the file uploads through the same progress pipeline and embeds as a video

#### Scenario: unsupported type is rejected

- Given the author drops a PDF into the editor
- Then an alert states the file type is unsupported
- And no upload starts

---

### Requirement: video embed popover upload tab

The video embed popover SHALL offer an Upload tab alongside the Embed (URL) tab, accepting local MP4 files subject to the same size gate, routed through the standard upload pipeline.

#### Scenario: author uploads a video from the popover

- Given the author opens the Video command and switches to the Upload tab
- When they select a valid MP4
- Then the file uploads and is inserted into the document as a video embed

---

### Requirement: image resizing

Images in the article editor SHALL be resizable via drag handles, with the chosen width persisted in the document so the public renderer reproduces it (bounded to a sane pixel range).

#### Scenario: resized image keeps its width on the public page

- Given the author drags an image to half width
- When the article is published and viewed publicly
- Then the image renders at the saved width, responsive on smaller viewports

---

### Requirement: pending-upload guards

The editor MUST expose whether uploads are pending (in flight or in error state). While a new article's create request is in flight, new uploads SHALL be blocked with an explanatory message. Navigation away from the editor with pending uploads MUST be intercepted with an alert and cancelled. Publishing MUST wait until no uploads are pending.

#### Scenario: navigation blocked during upload

- Given an upload is in flight
- When the author attempts to leave the editor page
- Then an alert explains an upload is still in progress
- And the navigation is cancelled

#### Scenario: post-create redirect is allowed through

- Given a new article whose create request has just succeeded
- When the editor redirects to the article's edit page
- Then the navigation guard does not block the redirect

#### Scenario: publish waits for uploads

- Given an upload in flight
- When the author triggers publish
- Then the publish action is deferred or blocked until the upload completes or is removed
