## Capability: conversation-attachments-panel

A "Shared Files" section in the conversation sidebar surfacing all attachments exchanged in the conversation (upstream: `SharedFiles.vue`, `components-next/SharedAttachments/*`, `GalleryView.vue` autoplay, eager-loaded attachments endpoint).

---

## ADDED Requirements

### Requirement: Shared Files sidebar section

The conversation sidebar SHALL include a "Shared Files" accordion listing the conversation's attachments grouped into media (images, video, audio) and files. The section MUST participate in the existing draggable sidebar section ordering and open/closed persistence. A loading spinner MUST show while attachments load, and an empty state MUST show when the conversation has no displayable attachments.

#### Scenario: media and files are grouped

- Given a conversation with 2 images, 1 video, and 3 PDFs
- When the user opens the Shared Files section
- Then a media grid shows the images and video and a files list shows the PDFs

#### Scenario: peek limits with expansion

- Given a conversation with more than 6 media items or more than 3 files
- Then the panel shows at most 6 media items and 3 files with a control to view the rest

#### Scenario: empty state

- Given a conversation with no attachments
- Then the section shows an empty-state message instead of lists

---

### Requirement: Attachment interaction

Selecting a media item SHALL open the gallery viewer for that attachment; video and audio MUST autoplay when opened this way. Selecting a file SHALL open its URL in a new browser tab.

#### Scenario: media opens gallery with autoplay

- Given a video attachment in Shared Files
- When the user selects it
- Then the gallery opens on that attachment and playback starts automatically

#### Scenario: file opens in new tab

- Given a PDF in the files list
- When the user selects it
- Then the PDF URL opens in a new tab (`noopener,noreferrer`)

---

### Requirement: Attachments endpoint performance

The conversation attachments API MUST eager-load attachment blobs, messages, inboxes, and sender avatars so the panel renders without N+1 queries, and MUST remain paginated.

#### Scenario: paginated eager-loaded response

- Given a conversation with many attachments
- When the attachments endpoint is queried with a page parameter
- Then the response includes the attachment page and total count
- And serving the page issues no per-row queries for blobs, messages, or sender avatars
