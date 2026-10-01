## Why

Konversio still ships the Dyte video-call integration from the v4.13.0 fork base. Upstream Chatwoot replaced Dyte with Cloudflare RealtimeKit in v4.16.0 via PR #14752 (merged 2026-06-24). Cloudflare's RealtimeKit is Dyte's v2 API re-hosted by Cloudflare — same endpoints, different base URL and auth — so Dyte accounts/credentials no longer track upstream and the integration must be re-pointed to keep working.

Upstream v4.16.0 changelog: *"The video call integration has moved from Dyte to Cloudflare RealtimeKit. If you use this integration, delete the existing Dyte integration and configure it again with your Cloudflare Account ID, RealtimeKit App ID, and an API token with Realtime Admin permissions."*

Upstream deliberately kept the `dyte` app id, routes, controller names, lib class, and i18n keys, swapping only the implementation underneath. Konversio follows upstream exactly (MIT-licensed verbatim port of PR #14752) — no rebrand to `realtimekit` in code.

## What Changes

- Re-point the video-call API client (`lib/dyte.rb`) from `api.dyte.io` to Cloudflare's RealtimeKit REST API: new base URL, Bearer-token auth, and a three-part credential set (`account_id`, `app_id`, `api_token`) instead of the legacy Dyte pair (`organization_id`, `api_key`).
- Add participant token lifecycle support: persist RealtimeKit participant ids on the integration message, refresh a stored participant's token on re-join instead of re-creating the participant, and recover from "participant already exists" by looking up the participant and refreshing their token.
- Add host-preset compatibility: add participants with the Cloudflare-format preset name, automatically retrying once with the legacy Dyte-format preset name when the provider reports the preset is missing.
- Add server-side validation of Cloudflare RealtimeKit credentials when an integration hook is created, its credentials change, or it is re-enabled, with specific user-facing error messages per failure mode.
- Grandfather existing Dyte hooks: hooks holding legacy credentials keep working untouched until their settings are edited; the new credential schema and validation are enforced only on create / credential change / status toggle. Call actions on legacy hooks short-circuit with an explanatory error.
- Update the integration settings form schema and copy (Cloudflare Account ID, RealtimeKit App ID, Cloudflare API Token), the integration name/description in `en.yml`, the meeting join URL (Cloudflare-hosted RealtimeKit meeting page), integration logos, and surface server-provided error messages on meeting-creation failure in the dashboard.

## Capabilities

### New Capabilities
- `realtimekit-credentials-validation`: Server-side verification of Cloudflare RealtimeKit credentials (API token validity, account access, RealtimeKit app existence) when a video-call integration hook is created or its credentials change, with per-failure-mode error reporting.
- `realtimekit-video-calls`: Cloudflare RealtimeKit-backed video/voice calls between agents and contacts, including meeting creation, namespaced participant identity, persisted participant tokens with refresh-on-rejoin, and legacy-credential grandfathering.

### Modified Capabilities
None.

## Impact

- `lib/dyte.rb` (rewritten internals; class name kept)
- `lib/integrations/dyte/processor_service.rb` (participant token lifecycle, legacy short-circuit)
- New `lib/integrations/cloudflare/realtime_kit_credentials_validator.rb`
- `app/models/integrations/hook.rb` (conditional credential validation, legacy-hook exemption)
- `app/controllers/api/v1/accounts/integrations/dyte_controller.rb`, `app/controllers/api/v1/widget/integrations/dyte_controller.rb` (pass message into processor service)
- `config/integration/apps.yml` (`dyte:` settings schema and form)
- `config/locales/en.yml` (new error strings; integration name/description — Konversio rebrand preserved)
- `app/javascript/shared/helpers/IntegrationHelper.js`, `app/javascript/dashboard/components/widgets/VideoCallButton.vue`
- `public/dashboard/images/integrations/dyte.png`, `dyte-dark.png` (logo swap)
- Specs: new validator spec; updates to dyte lib/processor/controller specs, hooks controller spec, hook model spec, and the `:dyte` hook factory trait
- No DB migration, no new env vars, no route or controller renames
- Ops note for existing installs: Dyte hooks must be deleted and re-created with Cloudflare credentials (upstream's documented migration path)
