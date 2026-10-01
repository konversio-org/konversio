## Capability: pilot-knowledge-markdown-documents

Markdown as a Pilot knowledge source type, alongside web pages and PDFs. Operators add markdown by uploading a `.md` file or pasting markdown text; the content becomes searchable knowledge immediately. Markdown documents are file-backed: they are never re-synced from a URL and never exposed as customer-visible citation links.

---

## ADDED Requirements

### Requirement: markdown documents can be created from upload or pasted text

The documents API SHALL accept markdown content either as a file upload or as pasted text. A pasted-text document MUST have its content stored directly, have a `.md` file synthesized from the text so both variants share one storage model, and become available immediately without entering the crawl pipeline.

#### Scenario: pasted markdown becomes available immediately

- Given an assistant under an account with Pilot enabled
- When a document is created with pasted markdown text
- Then the document stores the text as its content
- And a markdown file attachment is present with a `.md` filename
- And the document status is available without any crawl job running
- And the knowledge-rebuild pipeline runs so the content becomes searchable

#### Scenario: uploaded markdown file is stored as the document's source

- Given a valid `.md` file upload
- When the document is created
- Then the file is attached and its content becomes the document's content
- And the document status is available

#### Scenario: markdown documents receive a synthetic source link

- Given a markdown document created without an external link
- When the document is saved
- Then a synthetic, clearly file-backed link value is assigned
- And per-assistant uniqueness of source links continues to hold

---

### Requirement: markdown input is validated

Markdown documents MUST be rejected when the upload is not a `.md` file with a markdown or plain-text content type, when the content is empty, or when the content exceeds the markdown length cap (an order of magnitude below the web content cap, on the order of ten thousand characters). A document MUST NOT carry more than one file attachment across the supported file types.

#### Scenario: wrong file type is rejected

- Given an upload whose filename does not end in `.md` or whose content type is not markdown/plain text
- When the document is created
- Then validation fails with a format error and no document is persisted

#### Scenario: empty content is rejected

- Given a markdown document whose content is blank
- When the document is validated
- Then validation fails

#### Scenario: oversized content is rejected

- Given markdown content longer than the markdown length cap
- When the document is validated
- Then validation fails with a size error

#### Scenario: a document cannot attach both PDF and markdown files

- Given a document that already has a PDF attachment
- When a markdown file is also attached
- Then validation fails with a single-attachment error

---

### Requirement: markdown documents are file-backed for sync and citations

Markdown documents SHALL be classified as file-backed: they MUST be excluded from scheduled and manual refresh eligibility, MUST be rejected by the manual refresh endpoint, and MUST never produce a customer-visible citation URL.

#### Scenario: scheduler never picks markdown documents

- Given an available markdown document whose account's cadence window has elapsed
- When the scheduler evaluates due documents
- Then the markdown document is not enqueued

#### Scenario: manual refresh is rejected

- Given an available markdown document
- When a manual refresh is requested
- Then the response is a client error and no refresh job is enqueued

#### Scenario: no customer-visible source URL

- Given an available markdown document cited by a Pilot reply
- When customer-visible citation URLs are resolved
- Then the markdown document yields no citation URL
