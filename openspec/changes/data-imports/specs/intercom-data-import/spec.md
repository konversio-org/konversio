## Capability: intercom-data-import

Import contacts and conversations from an Intercom workspace via its REST API, using an access key, with rate-limit-aware background jobs, activity-event rendering, and truncation detection.

---

## ADDED Requirements

### Requirement: Intercom credential validation

The system SHALL validate an Intercom access key by making a minimal live API call (a one-record list request) per selected import type before an import is created. The client MUST pin a specific Intercom API version (upstream pins `2.15`) and authenticate with the access key as a bearer token.

#### Scenario: valid access key returns totals

- Given a valid Intercom access key and import types `contacts` and `conversations`
- When credentials are validated
- Then the response includes the workspace's contact total and conversation total when the API provides them

#### Scenario: rejected access key

- Given an access key Intercom rejects with an authentication error
- When credentials are validated
- Then the response is `422` indicating the access key and its permissions should be checked

---

### Requirement: Intercom contacts import

The system SHALL list Intercom contacts in pages (50 per page) following the API's `starting_after` pagination, and import each contact with name, email, E.164-normalized phone, external id (as `identifier`), last-activity timestamps, and source metadata (including the Intercom contact id) preserved in additional/custom attributes. Contacts with an email or phone MUST be created as `lead` type; contacts without either remain visitors until resolvable.

#### Scenario: contact fields mapped

- Given an Intercom contact with name, email, phone `14155552671`, and external id
- When it is imported
- Then the Konversio contact has the name, downcased email, phone `+14155552671`, and identifier set to the external id
- And additional attributes record the Intercom provider and source contact id

#### Scenario: invalid email or phone is dropped

- Given an Intercom contact whose email fails format validation and whose phone cannot be normalized to E.164
- When it is imported
- Then the contact is still imported with email and phone left blank rather than failing

#### Scenario: contact reference inside a conversation is resolved

- Given a conversation references a contact by id only (no inline email/phone/name)
- When the conversation is imported and no mapping exists for that contact
- Then the full contact is retrieved from the Intercom API before importing
- And a 404 from the contact endpoint falls back to the reference payload instead of failing

---

### Requirement: Intercom conversations import

The system SHALL list conversations in pages (10 per page), retrieve each conversation's full detail, and import the initial source message plus all conversation parts in order. Contact-authored parts SHALL map to incoming messages, admin/bot-authored parts to outgoing, and notes to private messages. Message content MUST be HTML-sanitized text (subject and body joined), with part and author metadata preserved in additional attributes.

#### Scenario: conversation with parts imports in order

- Given an Intercom conversation with a source message and three parts
- When it is imported
- Then a resolved Konversio conversation exists with four messages in source order
- And the conversation identifier is `intercom:<source id>`

#### Scenario: message authors attributed via contact mappings

- Given an incoming part authored by a contact already mapped from the contacts stage
- When the part is imported
- Then the message sender is the mapped Konversio contact

#### Scenario: truncated conversation parts are detected

- Given Intercom returns fewer conversation parts than the conversation's declared total
- When the conversation import finishes
- Then an `incomplete` log entry records the imported and total part counts
- And the entry is recorded only once per conversation across retries

---

### Requirement: Intercom activity events become activity messages

Non-message part types (assignments, opens, closes, snoozes, participant changes, attribute updates, and similar workflow events) SHALL be imported as activity-type messages with human-readable, translated content naming the actor (and target where applicable). Authors of type contact/lead/user SHALL render as "Contact"; bot or workflow authors as "Intercom automation"; otherwise "Intercom teammate".

#### Scenario: assignment event renders readable activity

- Given a part of type `assignment` authored by an Intercom admin targeting a teammate
- When it is imported
- Then an activity message is created whose content names the actor and the assignee

#### Scenario: unrecognized event type renders generic activity

- Given a part whose type has no specific translation
- When it is imported
- Then an activity message is created with generic wording including the event name

---

### Requirement: Rate-limit and transient-error resilience

Intercom page jobs SHALL automatically retry on client errors (3 attempts, one minute apart) and on rate-limit errors (5 attempts), failing the import only after attempts are exhausted. needs investigation: upstream v4.18.0's Intercom job base uses a fixed one-minute wait for rate-limit retries; whether it honors the API's `Retry-After` hint (as the Freshdesk base does) should be confirmed during the port and matched.

#### Scenario: rate-limited page job retries

- Given the Intercom API responds 429 to a page request
- When the page job runs
- Then the job is retried up to 5 times before the import is failed

#### Scenario: exhausted retries fail the import

- Given client errors on every attempt
- When retries are exhausted
- Then the import transitions to `failed` with the error recorded
