## Capability: whatsapp-identity

BSUID-aware contact identity for WhatsApp Cloud API channels: recognition of Meta's business-scoped user IDs alongside phone numbers, multi-identifier contact-inbox management, identifier synchronization, coexistence (WhatsApp Business app) onboarding support, ambiguity-safe phone lookup, and contact-info requests for phone-number-less contacts. All items in this capability are MIT ports of upstream core code.

---

## ADDED Requirements

### Requirement: BSUID recognition in message payloads

The system SHALL recognize BSUID identifiers (two uppercase letters, optional `ENT.` infix, up to 128 alphanumeric characters — e.g. `IN.2081978...`, `US.ENT.AB12...`) wherever WhatsApp payloads carry user identifiers: inbound messages (`from`, `from_user_id`, `from_parent_user_id`, contact `user_id`/`parent_user_id`), message echoes (`to`, `to_user_id`, `to_parent_user_id`), and delivery statuses (`recipient_user_id`, `recipient_parent_user_id`). Channel phone-number and Twilio address validation MUST accept BSUID-shaped identifiers in addition to E.164 digits.

#### Scenario: inbound BSUID-only message creates a conversation

- Given a whatsapp_cloud inbox
- When an inbound message webhook arrives with only a BSUID identifier and no phone number
- Then a contact and conversation are created anchored on the BSUID source ID

#### Scenario: phone-scoped channel validation unchanged

- Given the channel validation regexes
- When a plain E.164 phone number is validated
- Then it is accepted as before

---

### Requirement: Identity source-ID ordering preserves thread continuity

When a payload carries both a phone number and one or more BSUID identifiers, the system SHALL choose the primary source ID by history: phone history wins for mixed payloads, BSUID history wins if the contact was first seen BSUID-only, and brand-new mixed callers start on the phone number. Echoes MUST resolve through the same ordering as inbound messages so one contact never splits into two threads.

#### Scenario: phone history wins for mixed payload

- Given an existing contact-inbox anchored on a phone number with conversation history
- When an inbound message arrives carrying that phone number plus a BSUID
- Then the message lands on the existing phone-anchored conversation

#### Scenario: BSUID history wins when first seen BSUID-only

- Given an existing contact-inbox anchored on a BSUID with conversation history
- When an inbound message arrives carrying that BSUID plus a phone number
- Then the message lands on the existing BSUID-anchored conversation

#### Scenario: echo and inbound resolve identically

- Given a contact first seen via an outbound echo carrying a BSUID
- When the contact later sends an inbound message with the same identifiers
- Then the inbound message joins the same conversation thread

---

### Requirement: Identifier synchronization

The system SHALL maintain all known identifiers for a contact as additional `ContactInbox` rows on the inbox, and enrich the contact from identity data: set the phone number when newly revealed and unclaimed by another contact, record the WhatsApp username in social profile attributes, and promote a visitor-type contact to lead when a BSUID identity is seen. Concurrent webhook inserts of the same (inbox, source_id) pair MUST be treated as no-ops.

#### Scenario: new identifiers added on status webhooks

- Given an existing conversation
- When a delivery status webhook carries a previously unseen recipient BSUID
- Then a new contact-inbox row is created for that source ID on the same contact

#### Scenario: phone number backfilled when unclaimed

- Given a BSUID-only contact with no phone number
- When an identity payload reveals a phone number not used by any other contact in the account
- Then the contact's phone number is set

#### Scenario: phone number conflict leaves contact unchanged

- Given a BSUID-only contact and a different contact already owning the revealed phone number
- When the identity payload is processed
- Then the BSUID-only contact's phone number remains blank

---

### Requirement: User-ID rotation handling

Inbound system messages describing WhatsApp user-ID changes SHALL be processed so that messages following an identifier rotation continue to land on the existing contact and conversation rather than creating duplicates.

#### Scenario: rotation message keeps thread continuity

- Given a contact known under an old BSUID
- When a webhook delivers an identity-change system message followed by a message under a new BSUID
- Then the new message is attributed to the existing contact
- needs investigation: exact upstream rotation semantics in `Whatsapp::UserIdRotationService` (mapping payload fields to old/new identifiers) should be confirmed during implementation

---

### Requirement: Coexistence onboarding support

Embedded-signup authorization SHALL accept a coexistence flag (customer keeps using the WhatsApp Business app on the same number). For coexistence signups the system MUST NOT re-register the phone number with Meta, MUST subscribe the webhook to both `messages` and `smb_message_echoes` fields, and MUST skip the post-signup health check that would otherwise prompt reauthorization. When the flag is absent, a number already on the Business app (`is_on_biz_app` in health data) SHALL be detected and treated as coexistence.

#### Scenario: coexistence signup skips phone registration

- Given an embedded signup completion flagged as coexistence
- When webhooks are set up
- Then no phone-number registration call is made to Meta
- And the webhook subscription includes the message-echoes field

#### Scenario: explicit non-coexistence registers the number

- Given an embedded signup completion explicitly flagged as not coexistence
- When webhooks are set up
- Then the phone-number registration call is made

#### Scenario: implicit coexistence detected from health data

- Given an embedded signup completion with no coexistence flag
- And the channel health data reports the number is on the Business app
- When webhooks are set up
- Then phone registration is skipped

---

### Requirement: Ambiguity-safe phone lookup

Onboarding and reauthorization SHALL fetch the WABA's phone numbers with pagination and resolve the onboarded number authoritatively: by phone-number ID when provided, else by the channel's existing phone number, and MUST raise rather than guess when no identifier is available and the WABA holds multiple numbers.

#### Scenario: paginated fetch finds the number

- Given a WABA whose phone number list spans multiple Graph API pages
- When phone info is fetched during onboarding
- Then all pages are retrieved and the matching number is found

#### Scenario: reauthorization matches existing number

- Given a channel being reauthorized whose phone number differs from the WABA's first-listed number
- When phone info is fetched without a phone-number ID
- Then the channel's existing number is matched

#### Scenario: ambiguous WABA raises

- Given a coexistence completion providing only a WABA ID
- And the WABA holds more than one phone number
- When phone info is fetched
- Then an error is raised instead of selecting an arbitrary number

---

### Requirement: Contact-info requests for phone-less contacts

For whatsapp_cloud conversations whose contact has no phone number but a valid BSUID, agents SHALL be able to send a contact-information request asking the contact to share their phone number. The request is delivered as an interactive message inside the messaging window or as a configured template outside it, and its availability MUST be exposed per conversation. At most one request may be pending per contact-inbox.

#### Scenario: availability reported per conversation

- Given a conversation on a whatsapp_cloud inbox whose contact is BSUID-only
- When the conversation payload is loaded
- Then contact-info request availability is reported as available with the applicable delivery mode

#### Scenario: unavailable when phone already known

- Given a conversation whose contact already has a phone number
- When availability is computed
- Then the request is reported unavailable with a reason

#### Scenario: duplicate pending request blocked

- Given a conversation with a contact-info request already pending
- When another request is attempted
- Then it is rejected with a pending-request reason

#### Scenario: interactive mode requires open window

- Given a BSUID-only conversation outside the 24-hour messaging window
- When an interactive contact-info request is attempted
- Then it is rejected with an outside-window reason
- And template delivery remains possible when a suitable template is configured

#### Scenario: fulfillment stores the shared number

- Given a pending contact-info request
- When the contact responds sharing their phone number
- Then the contact's phone number is recorded and the request is marked fulfilled
- needs investigation: confirm the upstream webhook payload shape for contact-info responses and the exact fulfillment state values during implementation
