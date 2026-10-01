## Capability: freshdesk-data-import

Import contacts, tickets, public replies, and private notes from a Freshdesk account via its v2 REST API, using the account domain and an API key, with ticket-list pagination-cap handling and source-bucket inbox routing.

---

## ADDED Requirements

### Requirement: Freshdesk credential validation and domain normalization

The system SHALL accept a Freshdesk domain as a bare subdomain (`acme`), a full host (`acme.freshdesk.com`), or a URL, and normalize it to the `*.freshdesk.com` host, rejecting anything else with a clear validation error. Credentials (domain + API key) MUST be validated with a minimal live API call per selected import type before an import is created. The normalized domain MUST be persisted in the import's source metadata so later jobs reconstruct the client without re-asking the user.

#### Scenario: bare subdomain normalized

- Given the administrator enters `acme` as the domain
- When credentials are validated
- Then the client targets `acme.freshdesk.com`

#### Scenario: invalid domain rejected

- Given the administrator enters `acme.example.com`
- When credentials are validated
- Then the response is `422` instructing a valid Freshdesk domain such as `acme.freshdesk.com`

#### Scenario: invalid API key

- Given a valid domain with an API key Freshdesk rejects
- When credentials are validated
- Then the response is `422` indicating the API key and its permissions should be checked

---

### Requirement: Freshdesk contacts import

The system SHALL list Freshdesk contacts in pages (100 per page) and import them, mapping Freshdesk's `mobile` (preferred) or `phone` to the contact phone, `unique_external_id`/`external_id` to the identifier, and preserving other emails, custom fields, and tags in source metadata.

#### Scenario: contact fields mapped

- Given a Freshdesk contact with a name, email, mobile, and unique external id
- When it is imported
- Then the Konversio contact has the name, email, E.164-normalized mobile, and identifier
- And custom attributes record the Freshdesk contact id and external id

---

### Requirement: Freshdesk tickets import as conversations

The system SHALL list tickets in pages (100 per page) and import each ticket as a resolved conversation: the ticket description becomes the initial source message, and the ticket's replies and notes become subsequent messages in chronological order. Public replies SHALL map to incoming (requester-authored) or outgoing (agent-authored) messages; private notes MUST map to private messages. Ticket subject, status, priority, requester/responder/group/company ids, tags, custom fields, and archived flag SHALL be preserved in source metadata. The requester and any additional reply participants SHALL be imported as contacts; needs investigation: upstream derives outgoing source authorship from the ticket's numeric source value (outbound email and internal task sources are treated as agent-authored) — confirm the exact source ids during the port.

#### Scenario: ticket with replies and a private note

- Given a Freshdesk ticket with a description, two public replies, and one private note
- When it is imported
- Then a resolved conversation exists with the description as the first message, the replies in order, and the note as a private message
- And the conversation identifier is `freshdesk:<ticket id>`

#### Scenario: web chat ticket source handled

- Given a ticket whose source is Freshdesk's web chat
- When it is imported
- Then the ticket description/subject is not duplicated as a source message (the chat transcript parts carry the content)

---

### Requirement: Source-bucket routing for ticket channels

The system SHALL map each ticket's numeric Freshdesk source value to a source type name and group those into a small set of placeholder-inbox buckets (e.g. email, phone, chat, portal, social channels), with unrecognized sources routed to an "Unknown" bucket.

#### Scenario: ticket routed by source

- Given tickets sourced from email and from WhatsApp
- When they are imported
- Then they land in the "Freshdesk Import - Email" and "Freshdesk Import - WhatsApp" placeholder inboxes respectively

#### Scenario: unrecognized source routed to Unknown

- Given a ticket whose source value has no known mapping
- When it is imported
- Then it lands in the "Freshdesk Import - Unknown" placeholder inbox

---

### Requirement: Ticket-list pagination cap handling

The system SHALL detect Freshdesk's ticket list API pagination cap (300 pages, ~30,000 tickets at the default page size) and MUST NOT crash-loop when it is reached: the specialized ticket-limit error (`CustomExceptions::DataImport::FreshdeskTicketLimitError`) is raised and discarded at the job level without failing the import run. needs investigation: after the job chain is discarded the import is left non-terminal (it will eventually report stalled); how the UI should surface "import stopped at the API listing cap — a Freshdesk account export is required for remaining history" is not settled upstream.

#### Scenario: pagination cap reached

- Given a Freshdesk account with more tickets than the list API will paginate
- When the import reaches the final list page
- Then all tickets listed so far are imported
- And the ticket-limit error is raised once and the job discarded without failing or retrying the run

---

### Requirement: Rate-limit resilience honoring Retry-After

Freshdesk page jobs SHALL automatically retry on client errors (3 attempts, one minute apart) and on rate-limit errors (5 attempts), using the API's `Retry-After` hint as the retry delay when present and a one-minute default otherwise, failing the import only after attempts are exhausted.

#### Scenario: rate-limited job waits per Retry-After

- Given the Freshdesk API responds 429 with `Retry-After: 30`
- When the page job runs
- Then the retry is scheduled approximately 30 seconds later
