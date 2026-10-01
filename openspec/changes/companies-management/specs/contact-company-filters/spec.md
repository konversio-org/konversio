## Capability: contact-company-filters

Filtering and display glue between contacts, companies, and conversations: conversation filtering by contact, contact filtering by company name as a standard attribute, migration of the legacy company condition key, and a media view on the contact details page.

---

## ADDED Requirements

### Requirement: Conversation filter by contact

The conversation filter system SHALL support a standard numeric contact attribute on conversations with equality and inequality operators, so users can list exactly the conversations belonging to a chosen contact.

#### Scenario: filter returns one contact's conversations

- Given an account with conversations across several contacts
- When a conversation filter is applied for contact equality with a chosen contact
- Then only conversations of that contact are returned
- And mine/unassigned/all counts reflect the filtered set

#### Scenario: inequality excludes one contact

- When a conversation filter is applied for contact inequality with a chosen contact
- Then conversations of that contact are excluded from the result

#### Scenario: filter UI offers a contact picker

- Given the advanced conversation filter editor
- When the contact attribute is chosen
- Then the value input lets the user search and pick a contact rather than typing a raw id

---

### Requirement: Contact filter by company name

The contact filter system SHALL treat company name as a standard, case-insensitive text attribute sourced from the contact's denormalized company name, with text operators (equality, inequality, contains, does-not-contain).

#### Scenario: filter contacts by company

- Given contacts linked to companies
- When a contact filter matches company name against a value
- Then exactly the contacts whose denormalized company name matches are returned, regardless of letter case

#### Scenario: company appears in the contact filter editor

- Given the contact filter editor
- Then company name is offered as a standard attribute in the attribute list and grouping

---

### Requirement: Legacy company condition key migration

The system SHALL rename the legacy company condition key to the company-name key everywhere it was persisted as a standard (non-custom) attribute: automation rule conditions and saved contact custom filters.

#### Scenario: automation rules migrated

- Given an automation rule with a condition on the legacy company key as a standard attribute
- When the migration runs
- Then the condition references the company-name key
- And conditions using the legacy key as a custom attribute are left untouched

#### Scenario: saved contact filters migrated

- Given a saved contact filter whose query payload uses the legacy company key as a standard attribute
- When the migration runs
- Then the payload references the company-name key and the saved filter still returns the same contacts

#### Scenario: migration is irreversible-safe

- When the migration is rolled back
- Then it is a no-op and no data is corrupted

---

### Requirement: Contact media view

The contact details page SHALL include a media panel aggregating attachments from the contact's conversations, separated into media (images/video/audio) and files, with peek limits and links into the full attachment views.

#### Scenario: media grid

- Given a contact whose conversations contain image attachments
- When the contact details page is opened
- Then the media panel shows the newest media attachments (up to 12) as a grid
- And selecting one opens the gallery overlay

#### Scenario: files list

- Given a contact whose conversations contain non-media files
- Then the files section shows the newest files (up to 6)
- And selecting one opens the file in a new tab

#### Scenario: jump to message

- When the user chooses to locate an attachment's origin
- Then the app navigates to the conversation and message containing that attachment

#### Scenario: nothing shared yet

- Given a contact with no attachments
- Then the media panel is hidden or shows its empty state rather than a broken grid
