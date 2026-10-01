## Capability: whatsapp-setup

Guided setup for WhatsApp Cloud API inboxes: a manual setup v2 flow (credential preview/validation, one-step connect, webhook status and explicit webhook registration) with an in-app wizard, plus coexistence-aware embedded signup. All items in this capability are MIT ports of upstream core code.

---

## ADDED Requirements

### Requirement: Manual setup credential preview

The system SHALL expose `POST /api/v1/accounts/:account_id/whatsapp/manual/preview` accepting a WABA ID, phone-number ID, and access token, validating them against the Graph API and returning the resolved display phone number, verified name, and a suggested inbox name — without creating anything.

#### Scenario: valid credentials return preview

- Given a valid WABA ID, phone-number ID, and access token
- When preview is requested
- Then the response includes the display phone number, verified name, and suggested inbox name

#### Scenario: invalid credentials rejected

- Given an access token that cannot read the WABA or a phone-number ID outside the WABA
- When preview is requested
- Then the request fails with an unprocessable-entity error describing the failure
- And no channel or inbox is created

#### Scenario: phone number must belong to the WABA

- Given a valid token and WABA ID but a phone-number ID belonging to a different WABA
- When preview is requested
- Then validation fails
- needs investigation: confirm upstream's exact cross-WABA ownership check (`validate_phone_number_belongs_to_waba` in the manual setup validation service) including when the check is skipped vs enforced

---

### Requirement: Manual setup connect

The system SHALL expose `POST /api/v1/accounts/:account_id/whatsapp/manual/connect` that creates the whatsapp_cloud channel (marked with provider-config source `manual_setup_v2`) and inbox in one transaction, then attempts webhook registration, reporting the webhook outcome in the response so the UI can offer a retry — a webhook failure MUST NOT roll back the created inbox.

#### Scenario: successful connect

- Given valid credentials and an optional inbox name
- When connect is requested
- Then a channel and inbox are created
- And the response includes the inbox id, name, number/template access confirmations, and webhook setup success

#### Scenario: webhook failure reported, inbox kept

- Given valid credentials but a failing webhook subscription call
- When connect is requested
- Then the inbox is created
- And the response reports the webhook error

#### Scenario: inbox limit enforced

- Given an account at its inbox limit
- When connect is requested
- Then the request fails with the inbox-limit error and nothing is created

---

### Requirement: Manual webhook status and re-registration

For inboxes created via manual setup v2, the system SHALL expose `GET /api/v1/accounts/:account_id/whatsapp/manual/:inbox_id/webhook_status` reporting whether the webhook is correctly subscribed, and `POST .../setup_webhook` to (re)register the webhook and return the resulting status. Both endpoints MUST 404 for inboxes not created via manual setup v2.

#### Scenario: status reflects subscription state

- Given a manual-setup inbox whose webhook is subscribed
- When webhook status is requested
- Then the response indicates the webhook is configured

#### Scenario: setup webhook retries registration

- Given a manual-setup inbox whose initial webhook registration failed
- When setup webhook is requested
- Then registration is attempted again and the new status is returned

#### Scenario: non-manual inbox rejected

- Given an embedded-signup whatsapp inbox
- When webhook status is requested
- Then the request returns not-found

---

### Requirement: Guided setup wizard UI

The dashboard SHALL provide a guided WhatsApp setup wizard for manual Cloud API configuration: stepwise entry of WABA ID, phone-number ID, and access token with inline validation via preview, optional inbox naming, connect, and a webhook status/retry step, linking to documentation for obtaining credentials.

#### Scenario: wizard validates before connect

- Given the user has entered credentials in the wizard
- When they proceed
- Then the preview endpoint validates the credentials and shows the resolved number and name before anything is created

#### Scenario: wizard surfaces webhook failure with retry

- Given a connect that succeeded with a webhook error
- When the wizard shows the result
- Then the webhook error is displayed with a retry action that calls the setup-webhook endpoint

---

### Requirement: Coexistence-aware embedded signup

The embedded signup authorization flow SHALL accept and propagate a coexistence flag through channel creation and webhook setup, so customers migrating a number already used in the WhatsApp Business app keep both app and platform access (see `whatsapp-identity` for the webhook/registration behavior). Reauthorization of an existing inbox SHALL skip the post-signup health check to avoid false disconnect prompts.

#### Scenario: coexistence flag propagated

- Given an embedded signup completion with the coexistence flag set
- When the channel is created and webhooks configured
- Then the webhook setup runs in coexistence mode

#### Scenario: reauthorization skips health check

- Given an existing inbox being reauthorized
- When authorization completes
- Then no post-signup health check email/prompt is triggered
