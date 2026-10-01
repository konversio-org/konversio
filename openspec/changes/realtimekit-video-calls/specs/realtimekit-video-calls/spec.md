## Capability: realtimekit-video-calls

Cloudflare RealtimeKit-backed video/voice calls between agents and contacts, ported verbatim (MIT) from upstream Chatwoot PR #14752 (v4.16.0). The integration keeps its existing `dyte` app id, routes, class names, and i18n keys; only the provider internals, credential schema, and participant token lifecycle change.

---

## ADDED Requirements

### Requirement: Video-call API client uses Cloudflare RealtimeKit

The video-call API client (`lib/dyte.rb`) SHALL send requests to the Cloudflare API base URL (`https://api.cloudflare.com/client/v4`), scoped per account and app under `/accounts/{account_id}/realtime/kit/{app_id}/`, authenticating with a Bearer API token. The client MUST be constructed from the three-part credential set `account_id`, `app_id`, `api_token` and MUST raise an argument error when any of them is blank.

#### Scenario: client is built from hook settings

- Given an enabled `dyte` integration hook with settings `account_id`, `app_id`, `api_token`
- When a meeting is created or a participant is added
- Then requests go to `https://api.cloudflare.com/client/v4/accounts/{account_id}/realtime/kit/{app_id}/...`
- And the `Authorization` header is `Bearer {api_token}`

#### Scenario: missing credentials raise at construction

- Given any of `account_id`, `app_id`, `api_token` is blank
- When the client is constructed
- Then it raises an argument error reporting missing credentials

---

### Requirement: Host preset compatibility retry

When adding a participant, the client SHALL use the Cloudflare-format host preset name (`group-call-host`) and MUST automatically retry the same request once with the legacy Dyte-format preset name (`group_call_host`) when the provider response indicates the preset was not found.

#### Scenario: preset found on first attempt

- Given a RealtimeKit app that has the `group-call-host` preset
- When a participant is added to a meeting
- Then the participant is added with preset `group-call-host` and no retry occurs

#### Scenario: legacy preset fallback

- Given a RealtimeKit app that only has the legacy `group_call_host` preset
- When a participant is added and the provider responds with a preset-not-found error
- Then the client retries once with `group_call_host`
- And the participant is added successfully

---

### Requirement: Participant identity is namespaced and token-based

Participants SHALL be identified to RealtimeKit with a namespaced client id of the form `"<ModelName>:<id>"` (e.g. `User:42` for agents, `Contact:7` for contacts). A successful add-participant response SHALL expose the participant's join token under the `token` key, which the frontend uses to build the meeting join URL.

#### Scenario: agent joins from the dashboard

- Given an integration message with a `meeting_id`
- When an agent clicks to join the call
- Then the participant is registered with client id `User:{agent_id}`
- And the API response contains a `token` for the meeting join URL

#### Scenario: contact joins from the widget

- Given an integration message with a `meeting_id` in a widget conversation
- When the contact clicks to join the call
- Then the participant is registered with client id `Contact:{contact_id}`
- And the API response contains a `token` for the meeting join URL

---

### Requirement: Participant ids are persisted and refreshed on re-join

The processor service SHALL persist the RealtimeKit participant id for each client id on the integration message at `content_attributes.data.participants[client_id]`. When a user re-joins a meeting and a participant id is stored, the service MUST refresh the stored participant's token (via the provider's participant token endpoint) instead of creating a new participant. Persistence failures MUST be logged and MUST NOT fail the join.

#### Scenario: first join stores the participant id

- Given an integration message with no stored participant for `User:42`
- When agent 42 joins the meeting
- Then a participant is created with the provider
- And the returned participant id is stored at `content_attributes.data.participants['User:42']`

#### Scenario: re-join refreshes the stored token

- Given an integration message with a stored participant id for `User:42`
- When agent 42 joins the same meeting again
- Then the stored participant's token is refreshed and returned
- And no new participant is created

#### Scenario: participant exists provider-side but not in message data

- Given an integration message with no stored participant for `User:42`
- And a participant with custom participant id `User:42` already exists in the provider meeting
- When agent 42 joins
- Then the service lists the meeting's participants, matches by `custom_participant_id`
- And refreshes that participant's token instead of failing

---

### Requirement: Legacy Dyte credentials short-circuit call actions

When the integration hook's settings lack any of `account_id`, `app_id`, or `api_token` (legacy Dyte hooks holding `organization_id`/`api_key`), meeting creation and participant joins MUST short-circuit and return a localized error instructing the user to delete the existing Dyte integration and create it again with Cloudflare RealtimeKit credentials (`errors.dyte.realtimekit_credentials_required`).

#### Scenario: legacy hook attempts meeting creation

- Given an enabled `dyte` hook whose settings contain `organization_id` and `api_key` but none of the new keys
- When an agent clicks the video-call button
- Then no provider request is made
- And the response carries the `realtimekit_credentials_required` error message

#### Scenario: legacy hook attempts participant join

- Given an enabled `dyte` hook with legacy settings
- When a contact clicks to join an existing meeting from the widget
- Then no provider request is made
- And the response carries the `realtimekit_credentials_required` error message

---

### Requirement: Integration settings schema and form use Cloudflare credentials

The `dyte` entry in `config/integration/apps.yml` SHALL require `account_id`, `app_id`, and `api_token` (no additional properties), present form fields labeled "Cloudflare Account ID", "RealtimeKit App ID", and "Cloudflare API Token" (all required), and expose `account_id` and `app_id` as visible properties. The integration's display name in `en.yml` SHALL be "Cloudflare RealtimeKit" and its description MUST use "Konversio" (never "Chatwoot").

#### Scenario: settings form renders the new fields

- Given an admin opens the video-call integration settings
- Then the form shows fields for Cloudflare Account ID, RealtimeKit App ID, and Cloudflare API Token
- And all three are required

#### Scenario: legacy settings shape is rejected on save

- Given an admin saves the integration with `organization_id`/`api_key` settings
- When the settings JSON schema is enforced (new or edited hook)
- Then validation rejects the payload

---

### Requirement: Meeting join URL points to the Cloudflare-hosted RealtimeKit page

The meeting join URL builder (`IntegrationHelper.js`) SHALL use `https://examples.realtime.cloudflare.com/meeting/` as the base and construct the `authToken`, `showSetupScreen`, and `disableVideoBackground` query parameters safely (URL-encoded). needs investigation: whether Konversio should later self-host a RealtimeKit meeting UI instead of Cloudflare's hosted example page (the port follows upstream here).

#### Scenario: join URL is built from the token

- Given a participant token
- When the dashboard or widget builds the meeting link
- Then the URL targets the Cloudflare-hosted RealtimeKit meeting page with the token in the `authToken` query parameter

---

### Requirement: Meeting-creation failures surface the server error

When meeting creation fails, the dashboard video-call button SHALL display the server-provided error message (string error, or a nested provider error message) and MUST fall back to the generic create-error translation when no usable message is present.

#### Scenario: server returns a descriptive error

- Given the meeting-creation API responds with an error payload containing a message
- When the agent clicks the video-call button
- Then the alert shows that message

#### Scenario: no usable error detail

- Given the meeting-creation API fails without an error message
- When the agent clicks the video-call button
- Then the alert shows the generic `INTEGRATION_SETTINGS.DYTE.CREATE_ERROR` translation
