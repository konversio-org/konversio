## Why

Konversio's fork base (Chatwoot v4.13.0) predates upstream's dashboard onboarding wizard and all of the setup-assistance work shipped between v4.14.1 and v4.18.0. New accounts today land in an empty dashboard with no help connecting their first channel, no awareness of the signup domain's brand or mailbox provider, and no automatic Help Center bootstrap. OAuth channel connects initiated during onboarding drop the user into inbox settings instead of back into the setup flow. WhatsApp Cloud API setup remains a manual, error-prone credential hunt in Meta's developer console with no in-app guidance, and the health of a connected WhatsApp number (quality rating, messaging tier, webhook wiring) is not surfaced clearly to operators.

This change brings Konversio to parity with the onboarding and setup improvements shipped upstream in v4.14.1 ("onboarding improvements for Help Center generation and email detection"), v4.14.2 ("onboarding OAuth return flows and Help Center generation status"), v4.15.0 ("onboarding improvements for Help Center generation, OAuth redirects, and email provider detection"), and v4.18.0 ("guided WhatsApp setup and clearer account health").

## What Changes

- **Onboarding step flow** (MIT): a two-step onboarding wizard — account details, then inbox setup — tracked by an `onboarding_step` cursor in account `custom_attributes`, completed via `PATCH /api/v1/accounts/:account_id/onboarding`. Completing the account-details step provisions a web widget inbox from the collected website. Unlike upstream (which gates the inbox-setup step to Chatwoot Cloud), Konversio runs both steps on every installation.
- **Channel detection** (MIT): asynchronous brand enrichment after signup scrapes the account's website for title, colors, logo, and social profiles, and probes the domain's MX records to infer the mailbox provider (Google / Microsoft). Enriched data pre-fills the account-details form without clobbering user input, and detected social/email channels are suggested as one-click connects in the inbox-setup step.
- **OAuth return flows** (MIT): channel OAuth authorization requests initiated during onboarding carry a tamper-proof `return_to: 'onboarding'` hint through the OAuth `state` parameter; the Google, Microsoft, Instagram, and TikTok callbacks redirect the user back to the onboarding inbox-setup page instead of the inbox settings/agents pages.
- **Help Center generation** (EE-origin, clean-room): completing onboarding with a known website bootstraps a Help Center portal branded from the enriched brand data and kicks off a Pilot LLM pipeline that discovers help-content URLs on the site, plans categories and articles, and writes draft articles from the scraped source pages. A generation-status endpoint and a polling status row in the inbox-setup step show progress (generating / completed / skipped) and final article/category counts.
- **Guided WhatsApp setup** (MIT): a five-step guided manual setup flow for WhatsApp Cloud API — Meta app creation, phone number, and access token guidance with instructional videos, then credential validation/preview against the Meta API, then connect-and-verify with live checks for number access, template access, webhook callback configuration, and app subscription.
- **Clearer WhatsApp account health** (MIT): WhatsApp Cloud channels persist a `phone_number_health` snapshot refreshed by a scheduled sync job; the inbox settings health surface shows phone quality rating, status, messaging limit tier, display-name status, business profile, and expected-vs-actual webhook configuration, with a one-click webhook re-registration action.

## Capabilities

### New Capabilities
- `onboarding-step-flow`: Two-step onboarding wizard with a server-owned step cursor, account-details capture, and automatic web widget inbox provisioning.
- `onboarding-channel-detection`: Brand enrichment from the signup domain (website scrape + MX-record email provider inference), non-destructive form pre-fill, and detected-channel suggestions during inbox setup.
- `onboarding-oauth-return-flow`: Tamper-proof return hint threaded through channel OAuth state so callbacks route back into onboarding.
- `onboarding-help-center-generation`: Automatic branded Help Center portal creation plus a Pilot LLM pipeline that plans and drafts articles from the account's website, with a polled generation-status API and UI. (Clean-room re-expression of an upstream Enterprise feature.)
- `whatsapp-guided-setup`: Guided five-step manual setup wizard for WhatsApp Cloud API with server-side credential validation, inbox provisioning, and live webhook verification.
- `whatsapp-account-health`: Persisted WhatsApp phone-number health snapshot, scheduled health sync, and a clear account-health surface in inbox settings.

### Modified Capabilities
None.

## Impact

- `Account` model / `custom_attributes`: new `onboarding_step`, `brand_info`, and Help Center generation pointer keys.
- New `Api::V1::Accounts::OnboardingsController` (`PATCH update`, `GET help_center_generation`) and routes; `app_onboarding_inbox_setup` dashboard route.
- New services/jobs: `WebsiteBrandingService`, `Account::BrandingEnrichmentJob`, `Onboarding::WebWidgetCreationService` (MIT ports); `Pilot::` Help Center bootstrap/planner/writer services, generation tracker, and jobs (clean-room).
- `Api::V1::Accounts::OauthAuthorizationController` state signing, `OauthCallbackController`, `Instagram::CallbacksController`, `Tiktok::CallbacksController`, Instagram/TikTok integration helpers (return-hint handling).
- `Channel::Whatsapp`: new persisted health columns (`phone_number_health`, checked-at, error — migration required).
- New `Api::V1::Accounts::Whatsapp::ManualSetupController` (`preview`, `connect`, `webhook_status`, `setup_webhook`) and WhatsApp validation/setup/status services; health sync jobs.
- Frontend: new onboarding routes/components under `dashboard/routes/dashboard/onboarding/`; WhatsApp manual setup wizard and account-health components under inbox settings; English frontend i18n only for new labels and copy.
