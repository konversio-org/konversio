## Capability: upload-media-and-rendering-security

Active Storage direct-upload and streaming hardening, attachment type allowlisting including XML and PFX (PKCS#12) files, sanitization of URLs and sizing values in markdown/HTML rendering, and formula-injection-safe CSV exports.

---

## ADDED Requirements

### Requirement: The bare Active Storage direct-upload route is closed

Direct-upload blob creation MUST only be possible through the scoped, authenticated endpoints (dashboard and widget). Requests hitting the unscoped `ActiveStorage::DirectUploadsController` itself MUST be rejected with HTTP 403; scoped subclasses that add authentication MUST continue to work.

#### Scenario: anonymous direct upload is forbidden

- Given an unauthenticated client
- When it POSTs to the default Rails direct-upload route
- Then the response is HTTP 403 and no blob is created

#### Scenario: scoped conversation upload still works

- Given an authenticated agent
- When a direct upload is created through the account-scoped conversation endpoint
- Then the blob is created

---

### Requirement: Internal blob metadata cannot be set by clients

Direct-upload parameters MUST have the internal metadata keys `identified`, `analyzed`, and `composed` stripped before the blob arguments are built, so clients cannot forge analysis state.

#### Scenario: forged metadata is stripped

- Given an authenticated client creating a direct upload
- When the request includes `identified: true` in the blob metadata
- Then the stored blob metadata does not contain a client-supplied `identified` flag

---

### Requirement: Proxy streaming is range-limited

Active Storage proxy/streaming responses MUST honor at most one byte range per request and cap the total streamed range size at 100 MB; requests violating either constraint MUST receive HTTP 416 (range not satisfiable).

#### Scenario: multi-range request is rejected

- Given a media blob
- When a request asks for two byte ranges
- Then the response is HTTP 416

#### Scenario: oversized range is rejected

- Given a media blob
- When a request asks for a range larger than 100 MB
- Then the response is HTTP 416

---

### Requirement: Audio attachments are served inline

Audio content types (`audio/webm`, `audio/ogg`, `audio/mpeg`, `audio/mp4`, `audio/x-m4a`, `audio/wav`, `audio/x-wav`) MUST be served with inline content disposition so in-app players can stream them, and audio attachment event data MUST include a route-resolved `data_url`.

#### Scenario: voice note plays inline

- Given a message with an `audio/ogg` attachment
- When the attachment URL is fetched
- Then the response allows inline playback rather than forcing a download

---

### Requirement: XML and PFX attachments are accepted

The attachment allowlist MUST accept `text/xml` and `application/xml` content types and PKCS#12 content types (`application/x-pkcs12`, `application/pkcs12`). Files arriving with a blank or generic (`application/octet-stream`) content type MUST be accepted only when their extension is in the allowed extension list (`pfx`, `xml`, case-insensitive). All other disallowed types MUST remain rejected.

#### Scenario: PFX file with generic content type is accepted

- Given an upload of `cert.pfx` with content type `application/octet-stream`
- When the attachment is validated
- Then it is accepted

#### Scenario: executable with generic content type is rejected

- Given an upload of `run.exe` with content type `application/octet-stream`
- When the attachment is validated
- Then a "type not supported" validation error is added

---

### Requirement: Rendered markdown sanitizes link and image URLs

Server-side markdown rendering MUST strip URLs whose scheme is `javascript:`, `vbscript:`, `file:`, or `data:` from links and images, except `data:image/png`, `data:image/gif`, `data:image/jpeg`, and `data:image/webp` sources, while preserving application-internal protocols such as mention links. The same rules MUST apply in the frontend HTML sanitizer.

#### Scenario: javascript link is neutralized

- Given a message containing `[click](javascript:alert(1))`
- When the message is rendered
- Then the rendered anchor has an empty or stripped `href`

#### Scenario: safe data image is preserved

- Given a message containing an image with a `data:image/png;base64,...` source
- When the message is rendered
- Then the image source is retained

---

### Requirement: Image sizing values are bounded

Image sizing hints carried in URL query parameters MUST match a strict `<digits>px` shape and fall within 1–2000 pixels; valid values are emitted as inline style (width taking precedence over height), and anything else MUST be discarded so the attribute cannot be broken out of.

#### Scenario: valid width renders as inline style

- Given an image URL carrying a width hint of `640px`
- When rendered
- Then the `img` tag carries a style bounding the width to `640px` with responsive height

#### Scenario: injected sizing value is discarded

- Given an image URL whose sizing parameter contains quotes or non-numeric content
- When rendered
- Then no sizing style is emitted for that parameter

---

### Requirement: CSV exports are formula-injection safe and correctly encoded

All CSV export paths (contacts export job, report CSV views, CSAT download) MUST generate rows through the formula-injection-safe CSV library. The contacts export MUST prepend a UTF-8 BOM, restrict exportable columns to real contact columns plus the virtual `labels` column (preserving requested order, duplicates removed), and limit exported label values to titles of labels owned by the account.

#### Scenario: formula-leading cell is neutralized

- Given a contact whose name begins with `=`
- When the contacts CSV export is generated
- Then the cell is escaped so a spreadsheet does not evaluate it as a formula

#### Scenario: export opens with correct encoding

- Given contacts with non-ASCII names
- When the CSV is downloaded and opened in a spreadsheet application
- Then the UTF-8 BOM causes the names to display correctly

#### Scenario: labels column only contains account labels

- Given a contact tagged with a label title that does not exist in the account's label list
- When the CSV includes the labels column
- Then the foreign label title is not present in the export
