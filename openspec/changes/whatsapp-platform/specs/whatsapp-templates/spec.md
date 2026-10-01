## Capability: whatsapp-templates

Manage Cloud API and Twilio WhatsApp message templates in-app and via API: provider sync jobs, per-inbox template listing endpoints, and a Settings → Templates page with search, filters, sync triggering, and preview. All items in this capability are MIT ports of upstream core code.

---

## ADDED Requirements

### Requirement: Template sync per inbox

The system SHALL synchronize message templates from the provider into channel storage: Graph API `message_templates` for whatsapp_cloud channels (paginated, using the channel's template access token) and Twilio Content Templates for Twilio WhatsApp channels. Sync MUST run as a background job, update the channel's last-synced timestamp, and bump the account inbox cache key when the template set changed.

#### Scenario: cloud sync paginates

- Given a whatsapp_cloud channel whose WABA has more templates than one Graph API page
- When the sync job runs
- Then all pages are fetched and the full template set is stored

#### Scenario: sync updates cache key on change

- Given a channel whose stored templates differ from the provider's
- When the sync job completes
- Then the channel templates and last-synced timestamp are updated
- And the account inbox cache key is invalidated

#### Scenario: empty provider response keeps existing data

- Given a provider response with no template data
- When the sync job runs
- Then the channel's stored templates are left unchanged

---

### Requirement: Inbox template API

The inbox API SHALL expose `GET /api/v1/accounts/:account_id/inboxes/:id/message_templates` returning the channel's stored templates plus the last sync attempt timestamp (optionally filtered by template name), and `POST .../sync_templates` to enqueue a sync. Both endpoints MUST reject non-WhatsApp inboxes with an error.

#### Scenario: list templates for cloud inbox

- Given a whatsapp_cloud inbox with synced templates
- When `message_templates` is requested
- Then the response payload contains the templates and `meta.last_sync_attempt_at`

#### Scenario: list templates for Twilio WhatsApp inbox

- Given a Twilio WhatsApp inbox with synced content templates
- When `message_templates` is requested
- Then the response payload contains the content templates keyed by their display name

#### Scenario: filter by name

- Given an inbox with several templates
- When `message_templates` is requested with a `name` parameter
- Then only templates with that name are returned

#### Scenario: sync trigger enqueues job

- Given a WhatsApp inbox
- When `sync_templates` is requested
- Then the provider-appropriate sync job is enqueued and the request succeeds

#### Scenario: non-WhatsApp inbox rejected

- Given a non-WhatsApp inbox (e.g. email)
- When either endpoint is requested
- Then the request fails with an unprocessable-entity error

---

### Requirement: Templates settings page

The dashboard SHALL provide a Settings → Templates page aggregating templates across all WhatsApp inboxes (Cloud API and Twilio), with search by name/content, filters by inbox, language, and content type, a per-template preview drawer, a sync action across inboxes, and links to manage templates at the provider.

#### Scenario: aggregated listing

- Given two WhatsApp inboxes with distinct synced templates
- When the Templates page loads
- Then templates from both inboxes are listed, each annotated with its inbox(es)

#### Scenario: search and filters narrow the list

- Given the aggregated template list
- When the user types in search and selects a language filter
- Then only matching templates are shown
- And an empty-filter result shows a no-results state

#### Scenario: preview drawer

- Given a listed template
- When the user opens its preview
- Then a rendered preview of header, body, footer, and buttons is shown along with status, content type, category, language, and inbox metadata

#### Scenario: sync action feedback

- Given the Templates page
- When the user triggers template sync
- Then a sync is enqueued for all WhatsApp inboxes and the user sees success or partial-failure feedback

#### Scenario: template access token selection

- Given a whatsapp_cloud channel
- When templates are fetched from the Graph API
- Then the request authenticates with the channel's template access token (Konversio: the channel API key; the upstream Chatwoot Cloud business-management-token branch is out of scope for a self-hosted fork)
