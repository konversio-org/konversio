## Capability: widget-identity-verification

HMAC-based identity verification for web widget contacts, scoped to the identity-binding path so anonymous pre-chat updates keep working, with constant-time comparison and an admin endpoint to rotate the inbox identity-verification secret.

---

## ADDED Requirements

### Requirement: HMAC is enforced on identity-binding widget updates

Widget contact updates that supply an `identifier` (binding the session to a verified contact identity) MUST require a valid `identifier_hash` — the hex HMAC-SHA256 of the identifier keyed with the web widget's HMAC token — whenever the inbox enforces identity verification or a hash is supplied. Anonymous pre-chat updates (name, email, phone, custom attributes, without an identifier) MUST NOT require HMAC, including on HMAC-mandatory inboxes.

#### Scenario: identified update without a hash is rejected

- Given an HMAC-mandatory web widget inbox
- When a contact update supplies an `identifier` but no `identifier_hash`
- Then the response is 401 with an invalid-identifier-hash error

#### Scenario: anonymous pre-chat update works without HMAC

- Given an HMAC-mandatory web widget inbox
- When a contact update supplies only a name and email
- Then the update succeeds

#### Scenario: valid hash binds the identity

- Given a web widget inbox
- When a contact update supplies an `identifier` and a correctly computed `identifier_hash`
- Then the contact identity is updated and the contact inbox is marked HMAC-verified

---

### Requirement: Hash comparison is timing-safe

HMAC validation MUST first compare the byte length of the supplied hash against the expected digest and only then perform a constant-time comparison, rejecting mismatches with HTTP 401.

#### Scenario: wrong-length hash is rejected without comparison

- Given a supplied `identifier_hash` shorter than a SHA-256 hex digest
- When the widget update is validated
- Then the request is rejected with 401

---

### Requirement: Inbox identity-verification secrets can be rotated

An admin endpoint `POST /api/v1/accounts/:account_id/inboxes/:id/rotate_hmac_token` SHALL regenerate the identity-verification secret for web widget and API inboxes and return the updated inbox. The endpoint MUST return 404 for other inbox types. After rotation, previously valid `identifier_hash` values MUST no longer verify.

#### Scenario: rotation invalidates old signatures

- Given a web widget inbox whose secret is rotated
- When a widget update arrives with an `identifier_hash` computed from the old secret
- Then the request is rejected with 401

#### Scenario: rotation is rejected for unsupported inbox types

- Given an email inbox
- When the rotation endpoint is called
- Then the response is 404

#### Scenario: non-admin cannot rotate

- Given a non-admin agent
- When they call the rotation endpoint
- Then the response is 403
