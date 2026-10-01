## Why

Konversio forked Chatwoot at v4.13.0. Between v4.14.0 and v4.18.0 upstream rebuilt most of the WhatsApp surface: Meta's BSUID (business-scoped user ID) identifiers became first-class alongside phone numbers, template management moved in-app, campaign sending gained variables, processing states, and per-recipient delivery tracking, and inbox onboarding/health visibility was overhauled. Without these changes Konversio cannot reliably message BSUID-only contacts (increasingly common as Meta rolls out phone-number privacy), cannot run measurable WhatsApp campaigns, and gives operators no visibility into WhatsApp Business account health.

This change brings the Konversio WhatsApp platform to upstream v4.18.0 parity for the campaign, identity, template, health, setup, and conversation-context items, while re-implementing the one Enterprise-only piece (per-recipient campaign tracking/analytics) as a clean-room, requirements-level build in the core tree.

## What Changes

- **Campaign variables (v4.14.0, MIT):** Liquid variable interpolation in WhatsApp one-off campaign template parameters, resolved per contact with contact/agent/inbox/account drops, JSON-safe escaping, and skip-on-blank-render semantics; named and positional template parameter support including TEXT headers.
- **BSUID in message payloads (v4.14.1, MIT):** recognize BSUID identifiers in inbound messages, echoes, and delivery statuses; maintain multiple `ContactInbox` source IDs per contact; sync phone number / username / contact type from identity data.
- **Campaign processing status (v4.14.2, MIT):** new `processing` campaign status with `started_at`/`completed_at` timestamps and a locking guard so duplicate scheduler runs cannot double-send a one-off campaign.
- **Coexistence, BSUID, phone lookup, reply-window fixes (v4.16.1, MIT):** WhatsApp Business app coexistence onboarding (skip phone re-registration, subscribe to message echoes); paginated, ambiguity-safe phone-number lookup during onboarding/reauthorization; explicit failure for session messages sent outside the 24-hour messaging window; fuzzy WAMID token matching for quoted replies across phone-scoped and BSUID-scoped IDs.
- **Template management (v4.17.0, MIT):** list and sync Cloud API and Twilio WhatsApp templates via inbox API endpoints and a Settings → Templates page with search, filters, and preview.
- **Campaign delivery tracking and recipient outcomes (v4.17.0, EE → clean-room):** per-recipient lifecycle tracking for WhatsApp one-off campaigns, delivery-status reconciliation from webhooks, and an analytics API + dashboard (metrics breakdown and per-contact outcomes).
- **Click-to-WhatsApp referrals and Flow responses (v4.17.0, MIT):** persist ad referral metadata and WhatsApp Flow (nfm_reply) submissions on incoming messages and render them in the conversation view.
- **Account health and business profile (v4.17.1, MIT):** persist phone-number health data (quality rating, messaging limit, status, throughput, etc.) with checked-at/error bookkeeping, fetch the WhatsApp Business profile, expose both via the inbox health endpoint and inbox settings UI.
- **Guided WhatsApp setup (v4.18.0, MIT):** manual setup v2 flow — credential preview/validation, one-step connect that creates channel + inbox, webhook status polling and explicit webhook (re)registration — plus an in-app wizard.
- **BSUID-only campaigns and calls (v4.18.0, MIT):** resolve campaign destinations and call recipients for contacts that have only a BSUID, skip ambiguous identities, and block authentication-category templates to BSUID recipients.

## Capabilities

### New Capabilities
- `whatsapp-templates`: Sync, list, filter, and preview Cloud API and Twilio WhatsApp message templates in-app and via API.
- `whatsapp-campaigns`: One-off WhatsApp campaign execution with per-contact template variables, processing lifecycle, BSUID recipients, and per-recipient delivery tracking/analytics.
- `whatsapp-identity`: BSUID-aware contact identity resolution, identifier synchronization, coexistence onboarding support, phone lookup, and contact-info requests for phone-number-less contacts.
- `whatsapp-health-profile`: Persisted WhatsApp account health data and business profile visibility, exposed via API and inbox settings UI.
- `whatsapp-setup`: Guided manual setup and coexistence signup for WhatsApp Cloud API inboxes.
- `whatsapp-message-context`: Click-to-WhatsApp referral capture, Flow response capture, quoted-reply matching across identifier scopes, and messaging-window enforcement.

### Modified Capabilities
None.

## Impact

- `campaigns` table (`processing` status, `started_at`, `completed_at`) and `Campaign#trigger!` locking.
- New `pilot_campaign_recipients` table (clean-room recipient tracking; `pilot_` prefix per fork convention for new tables).
- `channel_whatsapp` (`phone_number_health`, `phone_number_health_checked_at`, `phone_number_health_error`) and `Channel::Whatsapp` (webhook setup variants, template access token, contact-info request).
- `lib/regex_helper.rb` BSUID/WAMID patterns; new identity services under `app/services/whatsapp/` (identifier sync, identity source ordering, user-ID rotation, in-reply-to finder, contact-info request services).
- `app/services/conversations/message_window_service.rb` consumers and `Whatsapp::SendOnWhatsappService` outside-window failure behavior.
- Inbox API: `GET /inboxes/:id/message_templates`, `POST /inboxes/:id/sync_templates`, `GET /inboxes/:id/health`, WhatsApp manual setup endpoints under `/whatsapp/manual/*`, campaign analytics endpoints under `/campaigns/:id/analytics/*`.
- Frontend: Settings → Templates pages, WhatsApp campaign analytics pages, inbox health components, guided manual setup wizard, referral/Flow rendering in message bubbles, `en.json`/`en.yml` i18n only.
- `Whatsapp::OneoffCampaignService`, template processor services, and campaign Vue forms.
