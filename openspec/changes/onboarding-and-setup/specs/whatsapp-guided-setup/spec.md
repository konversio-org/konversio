## Capability: whatsapp-guided-setup

Guided manual setup for WhatsApp Cloud API channels: a five-step wizard with instructional guidance for the Meta-side work, server-side credential validation and preview, transactional inbox provisioning, and live verification of number access, template access, webhook callback configuration, and app subscription. Reference implementation (MIT, verbatim port is legal): upstream `app/controllers/api/v1/accounts/whatsapp/manual_setup_controller.rb`, `app/services/whatsapp/manual_setup_validation_service.rb`, `app/services/whatsapp/manual_setup_service.rb`, `app/services/whatsapp/manual_webhook_status_service.rb`, `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/WhatsappManualSetup.vue`, and `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/ManualSetupVideo.vue`.

---

## ADDED Requirements

### Requirement: guided wizard structure

The WhatsApp channel add flow SHALL offer a guided manual setup path consisting of five steps: (1) Meta app creation guidance, (2) phone number guidance, (3) access token guidance — each with step-specific instructions and an instructional video — (4) credential entry (WhatsApp Business Account ID, phone number ID, access token) with validation and preview, and (5) review, connect, and verification. Steps 1–3 are informational; step 4 MUST NOT advance until the credentials validate against the Meta API.

#### Scenario: wizard advances through guidance steps

- Given a user opens the guided manual setup from the WhatsApp channel add flow
- When they navigate steps 1 through 3
- Then each step shows its instructions and instructional video
- And no API calls are made during the guidance steps

#### Scenario: credential step requires all fields

- Given the user is on the credential entry step
- When any of WABA ID, phone number ID, or access token is blank
- Then the verify action is blocked with an inline error

### Requirement: credential validation and preview

The system SHALL expose `POST /api/v1/accounts/:account_id/whatsapp/manual/preview` (restricted to users allowed to create inboxes) which validates the submitted credentials against the Meta API and returns a preview payload containing the verified business name, display phone number (normalized to `+<digits>`), phone number ID, WABA ID, template access flag, and a suggested inbox name.

Validation MUST reject with a descriptive error when: any parameter is blank; the phone number ID does not belong to the WABA; the phone number is neither connected nor ownership-verified at Meta; the display phone number or phone number ID is already used by another WhatsApp channel; the token cannot read message templates; or the token lacks the granted messaging permission.

#### Scenario: valid credentials return a preview

- Given a WABA ID, phone number ID, and access token with messaging and management permissions
- When preview is requested
- Then the response contains the verified business name, normalized display phone number, and a suggested inbox name combining them

#### Scenario: phone number not in WABA

- Given a phone number ID that belongs to a different WABA
- When preview is requested
- Then the response is HTTP 422 with an error explaining the mismatch

#### Scenario: phone number not verified at Meta

- Given a phone number whose Meta status is neither connected nor verified
- When preview is requested
- Then the response is HTTP 422 instructing the user to complete phone verification at Meta first

#### Scenario: duplicate number or phone ID

- Given another WhatsApp channel already uses the display phone number or the phone number ID
- When preview is requested
- Then the response is HTTP 422 identifying the duplicate

#### Scenario: insufficient token permissions

- Given a token that can read the phone number but cannot read message templates, or lacks the granted messaging permission
- When preview is requested
- Then the response is HTTP 422 explaining which permission to add

### Requirement: inbox provisioning via connect

The system SHALL expose `POST /api/v1/accounts/:account_id/whatsapp/manual/connect` which re-validates the credentials, creates a WhatsApp Cloud API channel (recording the access token, phone number ID, business account ID, and a `manual_setup_v2` source marker in `provider_config`) and its inbox in a single transaction, then attempts phone-number registration and webhook subscription. The response SHALL report number access, template access, whether webhook setup succeeded, and any webhook error — webhook failure MUST NOT fail inbox creation.

#### Scenario: connect creates the inbox

- Given valid credentials and an optional inbox name
- When connect is requested
- Then a `whatsapp_cloud` channel and inbox are created atomically
- And the inbox name is the submitted name or the suggested name from validation
- And the response is HTTP 201 with the new inbox id, name, access flags, and webhook outcome

#### Scenario: webhook failure still returns the inbox

- Given phone registration or webhook subscription fails at Meta
- When connect is requested
- Then the inbox is still created
- And the response includes the webhook error message with webhook setup marked unsuccessful

#### Scenario: inbox limit is enforced

- Given the account has reached its inbox limit
- When connect is requested
- Then the request is rejected with the existing inbox-limit error response

### Requirement: webhook status verification

The system SHALL expose `GET /api/v1/accounts/:account_id/whatsapp/manual/:inbox_id/webhook_status` (restricted to users allowed to update that inbox, and only for inboxes created via guided setup) reporting whether Meta has the expected callback URL configured for the phone number and whether the WABA has an active app subscription. `POST .../setup_webhook` SHALL retry phone registration and webhook subscription for such an inbox and return the refreshed status.

#### Scenario: status reflects Meta's configuration

- Given a guided-setup inbox whose phone number has the expected callback URL at Meta and whose WABA has a subscribed app
- When webhook status is requested
- Then the response reports the callback as configured and the subscription as verified, and includes the expected callback URL

#### Scenario: status is rejected for non-guided inboxes

- Given a WhatsApp inbox not created via guided setup
- When webhook status or setup is requested for it
- Then the response is HTTP 404

#### Scenario: retry repairs the webhook

- Given a guided-setup inbox whose webhook subscription failed during connect
- When setup webhook is requested
- Then registration and subscription are retried at Meta
- And the response returns the refreshed status

### Requirement: verification step behavior

After connect, the wizard SHALL display four verification rows — number access, template access, callback configured, subscription verified — poll the webhook status endpoint every 2 seconds for at most 5 attempts (stopping early when all rows pass), offer copying of the callback URL and a webhook retry action, and allow continuing to the add-agents screen regardless of the verification outcome.

#### Scenario: polling stops when all checks pass

- Given the connect succeeded with a webhook error
- When a subsequent poll reports callback configured and subscription verified
- Then polling stops and all four rows show as complete

#### Scenario: polling is bounded

- Given the webhook status never reaches all-pass
- When 5 poll attempts have completed
- Then polling stops and the incomplete rows remain visible with the retry action available
