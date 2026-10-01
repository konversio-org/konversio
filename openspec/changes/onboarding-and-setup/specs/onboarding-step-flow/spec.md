## Capability: onboarding-step-flow

Two-step onboarding wizard (account details → inbox setup) with a server-owned step cursor, account-details capture, and automatic web widget inbox provisioning. Reference implementation: upstream `app/controllers/api/v1/accounts/onboardings_controller.rb` and `app/services/onboarding/web_widget_creation_service.rb` (MIT — verbatim port is legal; Konversio drops the upstream cloud-only gate on the inbox-setup step).

---

## ADDED Requirements

### Requirement: onboarding step cursor on the account

The system SHALL track onboarding progress in `account.custom_attributes['onboarding_step']` with the known values `enrichment`, `account_details`, and `inbox_setup`, and SHALL reject step-completion requests for unknown steps with HTTP 422.

#### Scenario: unknown step is rejected

- Given an account in any onboarding step
- When an administrator submits `PATCH /api/v1/accounts/:account_id/onboarding` with an `onboarding_step` value outside the known set
- Then the response is HTTP 422
- And the account's stored step cursor is unchanged

#### Scenario: step completion requires an administrator

- Given a signed-in agent who is not an administrator
- When they submit a step-completion request
- Then the request is rejected as unauthorized

### Requirement: idempotent step completion

The onboarding API MUST only act while the stored cursor still points at the declared step, so stale or out-of-order replays are no-ops.

#### Scenario: replaying a completed step is a no-op

- Given an account whose cursor has already advanced past `account_details`
- When an administrator submits completion for `onboarding_step: account_details` again
- Then account attributes are not modified
- And no additional inboxes are created

#### Scenario: completing inbox setup finishes onboarding

- Given an account whose cursor is `inbox_setup`
- When an administrator submits completion for `onboarding_step: inbox_setup`
- Then the `onboarding_step` key is removed from `custom_attributes`
- And the dashboard router no longer redirects the account into onboarding

### Requirement: account details capture

Completing the `account_details` step SHALL persist the submitted account name and locale, and SHALL merge the submitted custom attributes (`industry`, `company_size`, `timezone`, `referral_source`, `user_role`, `website`) into `account.custom_attributes`.

#### Scenario: account details are stored on completion

- Given an account whose cursor is `account_details`
- When an administrator submits completion with name, locale, and custom attributes
- Then the account name and locale are updated
- And the submitted custom attributes are present in `account.custom_attributes`
- And the cursor advances to `inbox_setup`

### Requirement: web widget inbox provisioning

On completion of the `account_details` step the system SHALL provision a website live-chat inbox for the account asynchronously, reusing an existing web widget inbox when one exists and skipping provisioning when no website URL is known.

#### Scenario: widget inbox is created from the collected website

- Given an account with no web widget inbox and a known website URL
- When the `account_details` step completes
- Then a `Channel::WebWidget` channel and inbox are created in a single transaction
- And the completing user is added as an inbox member
- And the widget color is the first validated brand color (a `#rrggbb` hex) or a default color
- And the welcome title is the brand title or the account name
- And the welcome tagline is the brand tagline, truncated to at most 255 characters

#### Scenario: existing widget inbox is reused

- Given an account that already has a web widget inbox
- When the `account_details` step completes
- Then no additional web widget channel or inbox is created

#### Scenario: provisioning failure does not block onboarding

- Given widget provisioning raises an error
- When the `account_details` step completes
- Then the step completion still succeeds
- And the cursor advances to `inbox_setup`

### Requirement: onboarding UI follows the server-owned cursor

The dashboard SHALL route accounts with an active `onboarding_step` cursor into the matching onboarding screen, SHALL complete steps only through the onboarding API, and SHALL refresh the session user after final completion so the router guard observes the cleared cursor.

#### Scenario: inbox setup can be completed or skipped

- Given a user on the inbox-setup screen
- When they choose either continue or skip
- Then the client submits completion for `onboarding_step: inbox_setup`
- And the user is routed to the dashboard home

#### Scenario: onboarding route is served by the dashboard

- Given an account whose cursor is `inbox_setup`
- When the user navigates to `/app/accounts/:account_id/onboarding/inbox-setup`
- Then the dashboard application renders the inbox-setup screen
