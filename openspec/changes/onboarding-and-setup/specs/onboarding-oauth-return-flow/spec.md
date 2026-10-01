## Capability: onboarding-oauth-return-flow

A tamper-proof `return_to: 'onboarding'` hint threaded through the OAuth `state` parameter so channel connects initiated during onboarding route the user back to the onboarding inbox-setup page. Reference implementation (MIT, verbatim port is legal): upstream `app/controllers/api/v1/accounts/oauth_authorization_controller.rb`, `app/controllers/oauth_callback_controller.rb`, `app/controllers/instagram/callbacks_controller.rb`, `app/controllers/tiktok/callbacks_controller.rb`, `app/helpers/instagram/integration_helper.rb`, `app/helpers/tiktok/integration_helper.rb`, and `app/javascript/dashboard/routes/dashboard/onboarding/inbox-setup/useChannelConnect.js`.

---

## ADDED Requirements

### Requirement: onboarding return hint in the authorization request

Channel OAuth authorization endpoints SHALL accept an optional `return_to` parameter; the value `onboarding` SHALL be embedded in the OAuth `state` payload, and any other or absent value SHALL leave the state payload byte-identical to its current form so existing consumers are unaffected.

#### Scenario: onboarding connect tags the state

- Given an administrator on the onboarding inbox-setup screen
- When they start a Google, Microsoft, Instagram, or TikTok channel connect
- Then the authorization URL is requested with `return_to: 'onboarding'`
- And the issued OAuth `state` embeds the onboarding return hint inside the signed payload

#### Scenario: non-onboarding requests are unchanged

- Given an administrator connecting a channel from inbox settings
- When the authorization URL is requested without `return_to`
- Then the issued `state` payload is identical in form and content to what existing consumers receive today

### Requirement: hint is carried in a tamper-proof state payload

For Google and Microsoft the hint SHALL be expressed as a distinct purpose on the signed account Global ID used as `state`; for Instagram and TikTok it SHALL be a claim in the HMAC-signed JWT used as `state`. The hint MUST NOT be accepted from any unsigned parameter.

#### Scenario: forged hint is impossible

- Given an attacker crafts a callback request with an onboarding hint outside the signed payload
- When the callback processes the request
- Then the hint is not honored
- And a missing or unverifiable `state` is rejected as a bad request

#### Scenario: expired state is rejected

- Given a signed state whose validity window has elapsed
- When the callback resolves it
- Then the request is rejected and no inbox is created

### Requirement: callbacks route back to onboarding

When the resolved state carries the onboarding hint, a successful callback SHALL redirect the user to the onboarding inbox-setup page for that account; without the hint, existing redirect behavior MUST be preserved (settings page for an already-connected channel, agents page for a newly created inbox).

#### Scenario: onboarding Google connect returns to inbox setup

- Given an administrator started a Gmail connect from onboarding
- When the Google callback completes successfully
- Then the response redirects to `/app/accounts/:account_id/onboarding/inbox-setup`
- And the inbox-setup screen reflects the newly connected channel

#### Scenario: non-onboarding connect keeps existing routing

- Given an administrator started a Gmail connect from inbox settings
- When the callback completes successfully and the channel already existed
- Then the response redirects to the email inbox settings page
- And when the inbox is new, the response redirects to the add-agents page

#### Scenario: Instagram callback honors the hint

- Given an administrator started an Instagram connect from onboarding
- When the Instagram callback completes successfully
- Then the response redirects to `/app/accounts/:account_id/onboarding/inbox-setup`

#### Scenario: TikTok callback honors the hint

- Given an administrator started a TikTok connect from onboarding
- When the TikTok callback completes successfully
- Then the response redirects to `/app/accounts/:account_id/onboarding/inbox-setup`

#### Scenario: OAuth errors do not strand the user

- Given a callback fails or the user denies authorization
- When the provider redirects back with an error
- Then the existing error-page handling for that channel applies unchanged
