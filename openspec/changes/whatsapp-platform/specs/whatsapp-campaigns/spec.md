## Capability: whatsapp-campaigns

One-off WhatsApp campaign execution: per-contact template variables, a processing lifecycle that prevents duplicate sends, BSUID-aware recipient resolution, and per-recipient delivery tracking with analytics.

License note: template variables, processing lifecycle, and BSUID recipient resolution are MIT ports of upstream core code. Per-recipient delivery tracking and analytics are a CLEAN-ROOM re-implementation of an upstream Enterprise feature — requirements below are expressed functionally and must be implemented in the core tree as `Pilot::CampaignRecipient` (`pilot_campaign_recipients` table) without copying upstream enterprise code or UI copy.

---

## ADDED Requirements

### Requirement: Liquid template variables in campaign parameters

WhatsApp one-off campaign template parameters SHALL support Liquid-style variable expressions that are resolved individually for each audience contact before sending, with access to contact, sender (agent), inbox, and account attributes.

#### Scenario: variables resolved per contact

- Given a WhatsApp one-off campaign whose template body parameter contains a variable referencing the contact's name
- When the campaign is processed for two contacts with different names
- Then each contact receives a template message with their own name substituted

#### Scenario: blank render skips the contact

- Given a campaign template parameter whose variable resolves to a blank value for a given contact
- When the campaign is processed
- Then no message is sent to that contact
- And processing continues with the remaining audience

#### Scenario: variable values are safely escaped

- Given a contact attribute containing quotes or JSON-reserved characters
- When the variable is interpolated into template parameters
- Then the resulting parameter payload remains valid and the literal attribute value is preserved

#### Scenario: renderer failure does not abort the campaign

- Given one contact whose variable resolution raises an error
- When the campaign is processed
- Then that contact is skipped and logged
- And all other contacts are processed normally

---

### Requirement: Named and positional template parameters

Template parameter processing SHALL support both positionally-indexed (`1`, `2`, ...) and named template variables, and SHALL send positional parameters in numeric order; TEXT-format headers SHALL accept text parameters, while media headers SHALL be built from a media URL and type.

#### Scenario: positional parameters are ordered

- Given a template with positional variables and campaign parameters keyed `"2"` and `"1"`
- When the template payload is built
- Then parameters are emitted in ascending numeric order

#### Scenario: named parameters are passed by name

- Given a template declared with named parameters
- When the template payload is built
- Then each parameter carries its template variable name

#### Scenario: text header parameter

- Given a template with a TEXT header containing one variable
- And campaign header parameters providing a value
- When the template payload is built
- Then a header component with a text parameter is included

---

### Requirement: Campaign processing lifecycle

A one-off campaign SHALL transition through a `processing` status between `active` and `completed`, recording `started_at` when processing begins and `completed_at` when it completes, and MUST NOT send twice when multiple scheduler runs pick it up concurrently.

#### Scenario: campaign enters processing before sending

- Given an active one-off campaign whose scheduled time has arrived
- When it is triggered
- Then its status becomes `processing` and `started_at` is set before any message is sent

#### Scenario: duplicate trigger is a no-op

- Given a campaign already in `processing` or `completed` status
- When `trigger!` is invoked again
- Then no audience processing is executed and no duplicate messages are sent

#### Scenario: completion records timestamp

- Given a processing campaign whose audience has been fully processed
- When processing finishes
- Then the status becomes `completed` and `completed_at` is set

---

### Requirement: BSUID-only campaign recipients

Campaign delivery SHALL resolve a destination for contacts without a phone number using their BSUID contact-inbox entries for the campaign's inbox: a single BSUID identity is addressable, while multiple candidate identities MUST be skipped rather than guessed. Authentication-category templates MUST NOT be sent to BSUID recipients.

#### Scenario: phone number preferred

- Given a contact with both a phone number and a BSUID contact-inbox entry
- When the campaign resolves the destination
- Then the phone number is used

#### Scenario: single BSUID identity is addressable

- Given a contact with no phone number and exactly one BSUID contact-inbox entry on the campaign inbox
- When the campaign is processed
- Then the template message is sent to that BSUID

#### Scenario: ambiguous identities are skipped

- Given a contact with no phone number and more than one BSUID contact-inbox entry on the campaign inbox
- When the campaign is processed
- Then no message is sent to that contact and the skip is recorded

#### Scenario: authentication template blocked for BSUID

- Given a campaign using an authentication-category template
- And a BSUID-only contact in the audience
- When the campaign is processed
- Then no message is sent to that contact

---

### Requirement: Per-recipient delivery tracking (clean-room)

The system SHALL maintain one recipient record per (campaign, contact) for WhatsApp one-off campaigns, capturing the recipient's lifecycle status, the rendered message content sent to them, the provider message identifier, timestamps of each delivery milestone, and structured error details when delivery fails. Recipient records MUST be created for the full resolved audience before sending begins.

The lifecycle is: `queued` (created, not yet attempted) → `sent` (accepted by the provider) → `delivered` → `read`; `skipped` (never attempted, with reason) and `failed` (terminal provider error) are absorbing states.

#### Scenario: audience is materialized up front

- Given a WhatsApp one-off campaign with an audience of N contacts
- When campaign processing starts
- Then N recipient records exist in `queued` status, each linked to the campaign, account, inbox, and contact

#### Scenario: skipped recipient records the reason

- Given a contact whose destination cannot be resolved or whose template variables render blank
- When the campaign processes that contact
- Then the recipient record transitions to `skipped` with a human-readable reason

#### Scenario: successful send records provider identifier

- Given a queued recipient
- When the provider accepts the template message
- Then the recipient record transitions to `sent`, stores the provider message identifier and send timestamp, and captures the rendered message content

#### Scenario: send exception marks recipient failed, campaign continues

- Given a queued recipient whose send raises an unexpected error
- When the error is raised
- Then that recipient transitions to `failed` with error details
- And remaining recipients are still processed

---

### Requirement: Delivery status reconciliation (clean-room)

Inbound WhatsApp delivery status webhooks SHALL update the matching recipient record by provider message identifier. Status progression MUST be monotonic: a later lifecycle state is never overwritten by an earlier one, and failure reports arriving after `delivered` or `read` MUST NOT regress the recipient's status. Status event timestamps SHALL come from the provider's timestamp when present.

#### Scenario: delivered then read

- Given a recipient in `sent` status
- When a `delivered` status webhook arrives, then a `read` status webhook
- Then the recipient ends in `read` status with both `delivered_at` and `read_at` recorded

#### Scenario: out-of-order statuses do not downgrade

- Given a recipient in `read` status
- When a `delivered` status webhook arrives
- Then the recipient remains `read`
- And the missing `delivered_at` timestamp is backfilled if absent

#### Scenario: failure after delivery is ignored

- Given a recipient in `delivered` or `read` status
- When a `failed` status webhook arrives
- Then the recipient status is unchanged

#### Scenario: failure records structured error

- Given a recipient in `sent` status
- When a `failed` status webhook arrives carrying a provider error
- Then the recipient transitions to `failed` with `failed_at`, an error code, and a human-readable error message

#### Scenario: status arrives before recipient row is visible

- Given a delivery status webhook referencing a provider message identifier whose recipient record was committed very recently
- When no matching recipient is found
- Then the reconciliation is retried with backoff a bounded number of times before being abandoned with a warning

---

### Requirement: Campaign analytics API (clean-room)

The system SHALL expose, for WhatsApp one-off campaigns, an aggregate metrics endpoint and a paginated per-contact outcomes endpoint, scoped by the campaign's account and authorized like viewing the campaign itself.

#### Scenario: aggregate metrics

- Given a campaign with recipients in mixed statuses
- When an authorized user requests the analytics metrics
- Then the response includes the total audience size and counts per lifecycle status
- And a derived delivered count that includes recipients who later read the message
- And a sent count reflecting recipients with a recorded provider message identifier

#### Scenario: per-contact outcomes are paginated and filterable

- Given a campaign with more recipient records than one page
- When an authorized user requests the contacts endpoint with a page number and a status filter
- Then only recipients in that status are returned, paginated, with pagination metadata
- And each entry includes the contact's id, name, phone number, lifecycle status, rendered message content, and error details when present

#### Scenario: analytics restricted to WhatsApp one-off campaigns

- Given a campaign that is not a WhatsApp one-off campaign
- When the analytics endpoints are requested
- Then the request is rejected as not authorized

#### Scenario: cross-account access is denied

- Given a campaign belonging to another account
- When a user requests its analytics
- Then the request is rejected

---

### Requirement: Campaign analytics dashboard (clean-room)

The campaigns UI SHALL provide an analytics view for WhatsApp one-off campaigns showing aggregate delivery metrics, a per-status breakdown, and a paginated table of per-contact outcomes including failure reasons.

#### Scenario: analytics entry point from campaign list

- Given a WhatsApp one-off campaign with recipient data
- When the user opens the campaign from the campaigns list
- Then an analytics view is available showing the aggregate metrics

#### Scenario: per-contact table shows failure reasons

- Given recipients in `failed` status with recorded error details
- When the user views the per-contact outcomes table filtered to failures
- Then each row shows the contact, status, and the recorded error message
