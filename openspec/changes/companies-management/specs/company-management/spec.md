## Capability: company-management

Backend for companies in the core tree: an account-scoped `Company` model, a CRUD/search API, contact membership, aggregated notes and conversation history, custom attributes, avatar, activity tracking, automatic contact association from business email domains, and safe asynchronous deletion.

---

## ADDED Requirements

### Requirement: Company record and validations

The system SHALL store companies as account-scoped records with a required name, an optional domain, an optional description, a contacts counter, an activity timestamp, and two free-form attribute bags (system-written additional attributes and user-written custom attributes).

#### Scenario: name is required

- Given an account
- When a company is created without a name
- Then the creation is rejected with a validation error

#### Scenario: domain is unique per account when present

- Given an account with a company whose domain is `acme.com`
- When a second company is created in the same account with domain `acme.com`
- Then the creation is rejected with a validation error
- And a company in a different account MAY use the same domain

#### Scenario: domain must look like a hostname

- When a company is saved with a domain that is not a plausible dotted hostname (e.g. contains spaces or a scheme)
- Then the save is rejected with a validation error

#### Scenario: attribute bags default to empty objects

- Given a newly created company with no attributes supplied
- Then its additional attributes and custom attributes are empty maps, not nil

---

### Requirement: Companies API

The system SHALL expose an account-scoped REST API for companies supporting list, search, show, create, update, and delete, with payload fields sufficient for the dashboard (identity, domain, description, contacts count, avatar URL, custom attributes, activity and creation timestamps as unix time).

#### Scenario: list is paginated and sortable

- Given an account with more companies than one page holds
- When the list endpoint is requested with a page number and a sort parameter
- Then at most one page of results (25 companies) is returned with total-count metadata
- And sorting by name, domain, creation date, contacts count, or last activity is supported
- And companies with no recorded activity sort last when ordering by activity

#### Scenario: search requires a query

- When the search endpoint is requested without a query string
- Then the request is rejected with an unprocessable-entity error
- When requested with a query
- Then companies whose name or domain matches the query (case-insensitive, partial) within the account are returned, paginated like the list

#### Scenario: custom attributes merge on update

- Given a company with custom attribute `tier = "gold"`
- When the company is updated with custom attribute `region = "emea"` only
- Then the company has both `tier` and `region` afterwards

#### Scenario: custom attribute keys can be removed

- Given a company with custom attributes
- When the attribute-removal endpoint is called with an array of keys
- Then exactly those keys are removed
- When called with a non-array value
- Then the request is rejected with an unprocessable-entity error

#### Scenario: avatar can be removed

- Given a company with an attached avatar
- When the avatar endpoint is called with DELETE
- Then the avatar is detached and the company remains

---

### Requirement: Authorization rules

The system SHALL allow any account user to list, view, create, and update companies and to manage membership, custom attributes, and avatars, and SHALL restrict company deletion to account administrators.

#### Scenario: agent cannot delete

- Given a non-administrator account user
- When they request company deletion
- Then the request is rejected as not authorized

#### Scenario: administrator can delete

- Given an administrator
- When they request company deletion
- Then deletion is accepted and processed

---

### Requirement: Contact membership management

The system SHALL expose nested endpoints to list a company's member contacts, search candidate contacts, attach a contact to a company, and detach a contact from a company.

#### Scenario: member list is paginated

- Given a company with member contacts
- When the members endpoint is requested
- Then member contacts are returned paginated (15 per page) with total-count metadata
- And each entry includes the contact's company linkage state relative to the viewed company

#### Scenario: candidate search excludes current members

- Given a company with member contacts
- When the member-candidate search endpoint is queried by name, email, phone, or identifier
- Then matching account contacts that are not members of this company are returned
- When the query string is missing
- Then the request is rejected with an unprocessable-entity error

#### Scenario: attach seeds activity

- Given a contact with recorded activity
- When the contact is attached to a company
- Then the contact's company is set
- And the company's activity timestamp reflects the contact's latest activity

#### Scenario: detach clears linkage

- Given a member contact
- When the contact is detached from the company
- Then the contact's company linkage and denormalized company name are cleared
- And the contact and its conversations remain

---

### Requirement: Aggregated notes and conversation history

The system SHALL expose read-only nested endpoints returning the most recent notes written on a company's member contacts and the most recent conversations of a company's member contacts.

#### Scenario: notes aggregate across members

- Given a company whose members have notes written by multiple users
- When the notes endpoint is requested
- Then the newest notes across all member contacts are returned (bounded to 20), newest first, each including its contact and author

#### Scenario: history respects conversation permissions

- Given a company whose members have conversations, some in inboxes the requesting user cannot access
- When the history endpoint is requested
- Then only conversations visible under the standard conversation permission filter are returned
- And at most 20 conversations are returned, newest activity first

---

### Requirement: Activity tracking

The system SHALL maintain a last-activity timestamp on each company, advanced when member contacts record activity, with write throttling so hot ingest paths do not update the company on every event.

#### Scenario: contact activity advances company activity

- Given a member contact whose activity timestamp advances
- Then the company's activity timestamp is advanced to match, unless the stored value is already within the rollup window of the new timestamp

#### Scenario: throttle suppresses redundant writes

- Given a company whose activity was recorded moments ago
- When a member contact records new activity within the rollup window
- Then the company row is not rewritten

---

### Requirement: Denormalized company name on contacts

The system SHALL maintain the company's name inside each member contact's additional attributes so contact lists, sorting, filtering, and automations can use it without a join, and SHALL keep it consistent on rename and delete.

#### Scenario: name written on assignment and cleared on removal

- When a contact's company is set
- Then the contact's additional attributes contain the company's name
- When the contact's company is cleared
- Then the company-name entry is removed from the contact's additional attributes

#### Scenario: rename syncs members in the background

- Given a company with member contacts
- When the company is renamed
- Then a background job rewrites the denormalized company name on all member contacts in batches
- And the batch updates MUST NOT trigger contact callbacks, automations, or webhooks

---

### Requirement: Automatic association from business email domains

When a contact first gains an email address belonging to a business domain, the system SHALL associate the contact with the account's company for that domain, creating the company if none exists.

#### Scenario: new business email creates/links company

- Given a contact with no email and no company
- When an email at a business domain is saved on the contact for the first time
- Then the contact is linked to the account company for that domain, created on demand with a human-readable name derived from the domain
- And concurrent creation of the same domain company resolves to one record

#### Scenario: free-mail and disposable addresses never associate

- When a contact gains an address at a known free-mail provider, a disposable domain, or an invalid address
- Then no company association or creation occurs

#### Scenario: failures never block contact save

- When company association raises an error
- Then the contact save still succeeds and the error is logged

#### Scenario: existing membership is never overridden

- Given a contact already linked to a company
- When the contact's email changes to a different business domain
- Then the existing company linkage is preserved

---

### Requirement: Company deletion detaches contacts safely

The system SHALL delete companies asynchronously: a background job detaches member contacts (clearing linkage and the denormalized company name) in batches without firing contact callbacks, automations, or webhooks, and then destroys the company.

#### Scenario: delete returns immediately

- Given an administrator requests deletion
- Then the API responds successfully once the job is enqueued, before contacts are detached

#### Scenario: members are detached quietly

- Given a company with many member contacts
- When the deletion job runs
- Then all member contacts have no company linkage and no denormalized company name
- And no contact automations or webhooks fire as a result
- And the company record no longer exists
