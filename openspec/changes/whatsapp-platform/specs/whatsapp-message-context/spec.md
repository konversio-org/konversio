## Capability: whatsapp-message-context

Conversation-context enrichment for WhatsApp: Click-to-WhatsApp ad referral capture, WhatsApp Flow (nfm_reply) response capture and rendering, quoted-reply matching across identifier scopes, and explicit messaging-window enforcement on outgoing session messages. All items in this capability are MIT ports of upstream core code.

---

## ADDED Requirements

### Requirement: Click-to-WhatsApp referral capture

Inbound WhatsApp messages carrying ad referral metadata SHALL have that metadata persisted in message content attributes and rendered in the conversation view as a referral/ad card. Echo messages MUST NOT record referral data.

#### Scenario: referral metadata stored

- Given an inbound message webhook containing a `referral` object (ad source URL, source type, headline, body, media)
- When the message is created
- Then the referral object is stored in the message's content attributes

#### Scenario: referral visible in conversation

- Given a message with referral content attributes
- When the conversation is viewed
- Then the referral information is rendered alongside the message

#### Scenario: echoes skip referral capture

- Given an outgoing echo payload containing a `referral` object
- When the echo is processed
- Then no referral content attributes are recorded

---

### Requirement: WhatsApp Flow response capture

Inbound messages containing a Flow submission (`interactive.nfm_reply`) SHALL store the flow name, body, and parsed response JSON in message content attributes, use a localized placeholder as the message text, and render the submitted responses in the conversation view.

#### Scenario: flow submission stored

- Given an inbound message with an `nfm_reply` interactive payload
- When the message is created
- Then content attributes contain the flow name, body, and parsed response JSON
- And the message content is a localized "flow response" placeholder

#### Scenario: malformed response JSON kept raw

- Given an `nfm_reply` whose response JSON fails to parse
- When the message is created
- Then the raw response string is preserved instead of dropping the submission

#### Scenario: flow response rendered

- Given a message with flow response content attributes
- When the conversation is viewed
- Then the submitted field values are rendered in the message bubble

---

### Requirement: Quoted-reply matching across identifier scopes

Quoted-reply resolution SHALL match the referenced provider message ID exactly first, then fall back to matching the embedded message token across phone-scoped and BSUID-scoped WAMIDs; an ambiguous token match (multiple distinct messages sharing the token) MUST resolve to no match rather than guessing.

#### Scenario: exact source ID match

- Given a conversation containing a message with the exact referenced source ID
- When the quoted reply is processed
- Then the reply is linked to that message

#### Scenario: cross-scope token match

- Given a conversation containing a message whose WAMID shares the embedded token with the referenced ID but differs in scope prefix
- When the quoted reply is processed
- Then the reply is linked to that message

#### Scenario: ambiguous token resolves to none

- Given two messages in the conversation whose WAMIDs share the referenced token
- When the quoted reply is processed
- Then no in-reply-to link is created

#### Scenario: undecodable ID resolves to none

- Given a referenced ID that is not a decodable WAMID
- When the quoted reply is processed
- Then only exact matching applies

---

### Requirement: Messaging-window enforcement on outgoing replies

Outgoing WhatsApp session (non-template) messages SHALL only be sent while the conversation's messaging window is open; outside the window the message MUST be marked failed with a localized "outside messaging window" error instead of attempting a send. Template messages remain sendable outside the window.

#### Scenario: session message inside window sends

- Given a conversation with a recent inbound message inside the window
- When an agent sends a regular reply
- Then it is delivered as a session message

#### Scenario: session message outside window fails explicitly

- Given a conversation whose messaging window has closed
- When an agent sends a regular (non-template) reply
- Then the message status becomes failed with the localized outside-window error
- And no provider send is attempted

#### Scenario: template message outside window sends

- Given a conversation whose messaging window has closed
- When an agent sends a template reply
- Then the template message is sent to the provider

---

### Requirement: BSUID-only call addressing

Outbound WhatsApp call initiation SHALL resolve callees without a phone number via their BSUID contact-inbox entries, following the same selection rules as campaign destinations (single BSUID addressable, ambiguous identities rejected).

#### Scenario: call placed to BSUID-only contact

- Given a contact with no phone number and exactly one BSUID contact-inbox entry on the calling inbox
- When an agent initiates a WhatsApp call
- Then the call is addressed to that BSUID

#### Scenario: ambiguous identity blocks the call

- Given a contact with multiple BSUID identities and no phone number
- When call initiation is attempted
- Then it is rejected rather than addressed to an arbitrary identity
- needs investigation: upstream call services live in the enterprise overlay; confirm the Konversio call subsystem's home and the exact callee-addressing payload before implementation
