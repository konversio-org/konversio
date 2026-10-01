## Capability: help-center-analytics-integrations

Portal owners can connect standard analytics providers to their public Help Center. Configured tracking snippets are injected into every public portal page; configuration values are strictly validated and writable only by administrators.

MIT port: references upstream core-tree files (`Portal::ANALYTICS_CONFIG_FORMATS` in `app/models/portal.rb`, `PortalsController` param handling, `app/views/layouts/_portal_analytics*.html.erb`, `PortalIntegrationsSettings.vue`).

---

## ADDED Requirements

### Requirement: per-portal analytics provider configuration

A portal SHALL store analytics provider identifiers under `config.analytics`, supporting: Google Tag Manager container id, Google Analytics 4 measurement id, Hotjar site id, Plausible domain, Amplitude API key, Microsoft Clarity project id, and Meta pixel id. Each value MUST be validated against a per-provider format allowlist (prefix/shape constraints that guarantee the value is safe to interpolate into markup). Invalid values MUST be rejected at the model layer. Unknown analytics keys MUST be rejected with `422` before save.

#### Scenario: valid identifiers are accepted

- Given an administrator updates a portal with a GA4 measurement id of shape `G-XXXXXXXXXX` and a Plausible domain
- When the portal is saved
- Then both values are stored under `config.analytics`

#### Scenario: malformed identifier is rejected

- Given an update with a GTM container id missing the `GTM-` prefix
- When the portal is saved
- Then validation fails with an error naming the invalid field
- And no analytics values are persisted

#### Scenario: unknown analytics key is rejected

- Given an update containing `config.analytics.custom_tracker`
- When the portal update API is called
- Then the response is `422 Unprocessable Entity`

---

### Requirement: administrator-only writes

The portal update API MUST permit analytics config keys only for account administrators. Requests from non-administrators SHALL silently exclude analytics keys from the permitted params (other permitted portal settings still save).

#### Scenario: admin can save analytics

- Given an administrator
- When they update the portal's analytics config
- Then the values persist

#### Scenario: non-admin analytics keys are ignored

- Given a non-administrator with portal management rights
- When they submit an update including analytics keys
- Then the response succeeds
- And the portal's analytics config is unchanged

---

### Requirement: snippet injection on public portal pages

Every public portal page SHALL include, in the document head, the tracking snippet of each configured provider, and any provider-required noscript fallback immediately after the body opens. Snippets MUST interpolate only the validated identifier (no other user input). When no providers are configured, no analytics markup is emitted.

#### Scenario: configured providers appear on public pages

- Given a portal configured with GA4 and Meta pixel ids
- When a visitor loads any public page of the portal
- Then the page head contains the GA4 and Meta pixel snippets with the configured ids

#### Scenario: unconfigured portal emits nothing

- Given a portal with no analytics config
- When a visitor loads a public page
- Then the response contains no analytics snippets or noscript fallbacks

---

### Requirement: Integrations tab in Portal Settings

Portal Settings SHALL include an Integrations tab offering one input per analytics provider with per-provider client-side format validation and icons, dirty tracking (save enabled only when values changed), and the existing live-chat web-widget selector relocated from the base settings. The tab MUST reflect that analytics configuration is administrator-only.

#### Scenario: inputs prefill from the portal config

- Given a portal with a configured Hotjar site id
- When an admin opens the Integrations tab
- Then the Hotjar input shows the stored id and other provider inputs are empty

#### Scenario: invalid format blocks save client-side

- Given an admin types a malformed GA4 id into its input
- When they attempt to save
- Then client-side validation flags the field before any API call

#### Scenario: live chat widget selector lives in Integrations

- Given an admin opens the Integrations tab
- Then they can attach or detach a web-widget inbox as the portal's live chat widget
- And the base settings no longer duplicate that control
