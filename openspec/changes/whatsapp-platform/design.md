## Context

Konversio is a hard fork of Chatwoot v4.13.0 with no upstream tracking. The fork removed the `enterprise/` overlay and renamed Captain to `Pilot::`; it is 100% MIT and self-hosted only, so there is no OSS/Enterprise split to preserve and no Chatwoot Cloud.

Between v4.13.0 and v4.18.0 upstream reworked the WhatsApp platform across the core tree (MIT) and the enterprise overlay (EE). This change covers the campaign/identity/template/health/setup/conversation-context portion of that delta. The upstream reference material is a shallow clone with tags `v4.13.0` and `v4.18.0`; intermediate release attribution comes from the changelogs.

**License axis (mixed).** Per sub-item:

- MIT (port-reference allowed, verbatim porting legal): campaign variables (v4.14.0), BSUID payload support (v4.14.1), campaign processing status (v4.14.2), coexistence/BSUID/phone-lookup/reply-window fixes (v4.16.1), template management in-app and via API (v4.17.0 core), Click-to-WhatsApp referrals and Flow responses (v4.17.0), account health and business profile (v4.17.1), guided setup (v4.18.0), BSUID-only campaigns and calls (v4.18.0).
- EE → clean-room, requirements-level only: per-recipient campaign delivery tracking and recipient-outcome analytics (v4.17.0, `[Enterprise]`). Upstream implementation (`enterprise/app/models/campaign_recipient.rb`, `enterprise/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb`, `enterprise/app/jobs/campaigns/update_recipient_status_job.rb`, `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb`) was read for understanding only; the spec expresses functional requirements in original wording and targets Konversio's core-tree architecture.

## Goals / Non-Goals

**Goals:**

- Reach functional parity with upstream v4.18.0 for the assigned WhatsApp items.
- Keep all code in the core tree (`app/`, `lib/`, `app/javascript/`) — no `enterprise/` directory, no `prepend_mod_with` overlays.
- Express the EE recipient-tracking capability as a clean-room functional spec implementable without reference to upstream expression.
- Reuse upstream MIT code by porting files where the license permits, adapting naming to Konversio conventions.
- Preserve existing conversation history continuity when contacts gain or reveal identifiers (phone ↔ BSUID).

**Non-Goals:**

- WhatsApp voice calling subsystem itself (upstream `whatsapp_calls` controllers/services are a separate parity item); this change only requires that call initiation resolve BSUID-only callees.
- 360dialog ("default" provider) template sync improvements beyond what v4.13.0 already had.
- Chatwoot Cloud-only machinery: the `business_management_token` column / `template_access_token` cloud branch exist upstream for Chatwoot Cloud embedded signup; Konversio uses the channel's own API key as the template access token.
- SMS (non-WhatsApp) campaign changes beyond the shared `processing` status.
- Captain/Pilot AI features; nothing here touches `Pilot::`.

## Decisions

### Port MIT items from upstream, adapted to the core tree

For MIT sub-items, upstream files may be ported verbatim (MIT license) and then adapted: drop `*.prepend_mod_with(...)` / `include_mod_with` trailer lines, drop enterprise branches, and adjust i18n keys that mention Chatwoot per the fork's branding guidance (`replaceInstallationName` for user-facing brand strings).

Reference upstream files per item:

- Campaign variables: `app/services/whatsapp/liquid_template_processor_service.rb`, `app/services/whatsapp/template_content_renderer_service.rb`, `app/services/whatsapp/template_processor_service.rb`, `app/services/whatsapp/populate_template_parameters_service.rb`, drops (`app/drops/contact_drop.rb` etc.).
- Processing status: `app/models/campaign.rb` (`processing` enum value, `started_at`/`completed_at`, `trigger!` lock).
- BSUID identity: `lib/regex_helper.rb` (BSUID/WAMID patterns), `app/services/whatsapp/incoming_message_identifier_helper.rb`, `identifier_sync_service.rb`, `identity_source_id_orderer.rb`, `user_id_rotation_service.rb`, `contact_inbox_source_id_resolver.rb`, `in_reply_to_message_finder.rb`, `phone_normalizers/*`, `incoming_message_service_helpers.rb`, `webhook_channel_finder_service.rb`.
- Coexistence / phone lookup: `app/services/whatsapp/embedded_signup_service.rb`, `webhook_setup_service.rb`, `phone_info_service.rb`, `facebook_api_client.rb`.
- Reply window / contact info requests: `app/services/whatsapp/send_on_whatsapp_service.rb`, `contact_info_request_eligibility_service.rb`, `contact_info_request_service.rb`, `contact_info_response_service.rb`, `providers/whatsapp_cloud_contact_info_request_service.rb`, `app/controllers/api/v1/accounts/conversations/contact_info_requests_controller.rb`.
- Templates: `app/controllers/api/v1/accounts/concerns/inbox_health_management.rb` (`message_templates`, `sync_templates`), `app/jobs/channels/whatsapp/templates_sync_job.rb`, `app/jobs/channels/twilio/templates_sync_job.rb`, `app/services/whatsapp/providers/whatsapp_cloud_service.rb` (paginated template fetch), Twilio content-template sync, frontend `app/javascript/dashboard/routes/dashboard/settings/templates/*`.
- Health / profile: `app/services/whatsapp/health_service.rb`, `business_profile_service.rb`, `Channel::Whatsapp` health columns, frontend `settings/inbox/components/AccountHealth.vue`, `InboxHealthState.vue`.
- Guided setup: `app/controllers/api/v1/accounts/whatsapp/manual_setup_controller.rb`, `app/services/whatsapp/manual_setup_service.rb`, `manual_setup_validation_service.rb`, `manual_webhook_status_service.rb`, frontend `settings/inbox/channels/WhatsappManualSetup.vue`.
- CTWA / Flow: `incoming_message_service_helpers.rb` (referral + nfm_reply extraction), message bubble components under `app/javascript/dashboard/components-next/`.
- BSUID-only campaigns/calls: `app/services/whatsapp/oneoff_campaign_service.rb` (`campaign_destination`), `app/services/whatsapp/authentication_template_guard.rb`.

Alternatives considered:
- Cherry-picking upstream commits: rejected — no upstream tracking, and the fork's history has diverged; port-by-file with review is auditable.
- Re-deriving MIT behavior from scratch: rejected — needless clean-room cost for MIT code we may legally port.

### Clean-room the EE recipient-tracking capability

Per-recipient campaign tracking is EE upstream, so it is specced as functional requirements: a recipient lifecycle (queued → sent → delivered → read, with terminal skipped/failed), per-recipient rendered content capture, webhook status reconciliation that never downgrades status, an analytics API (aggregate metrics + paginated per-contact outcomes), and a campaign analytics dashboard. All wording, data shapes, and UI copy are original. Status names mirror Meta's webhook delivery states (an external platform contract), not upstream taxonomy.

Alternatives considered:
- Port the upstream EE files: rejected — EE license forbids it.
- Track outcomes only on messages, not recipients: rejected — campaign sends to contacts without a conversation do not produce messages, so a dedicated recipient record is the only reliable source.

### Recipient table lands in core with a `pilot_` prefix

The recipient-tracking table is a new table introduced by clean-room EE-parity work, so per fork convention it is named `pilot_campaign_recipients` and its model `Pilot::CampaignRecipient`, even though it is not an AI feature. Everything lands in `app/`, `lib/`, and standard spec paths — no `enterprise/` directory is created.

Alternatives considered:
- Plain `campaign_recipients` in core: simpler, but violates the fork's stated convention that new tables take `pilot_` prefixes; mixing conventions now makes future parity audits harder.

### Keep the `whatsapp_campaign` account feature flag

Upstream gates WhatsApp campaigns behind the `whatsapp_campaign` account feature flag. Konversio keeps the flag mechanism (it lives in core) and enables it for accounts that should run campaigns; there is no cloud-plan gating in a self-hosted fork.

Alternatives considered:
- Remove the flag: rejected — instance admins may still want per-account control, and removing it diverges further from the ported MIT code.

### BSUID identity resolution preserves thread continuity

When a payload carries both a phone number and one or more BSUIDs, the system must anchor on the identifier that already has conversation history: phone history wins for mixed payloads, BSUID history wins if the contact was first seen BSUID-only, and brand-new mixed callers start on the phone number (upstream `Whatsapp::IdentitySourceIdOrderer` semantics, MIT). Echoes must resolve through the same ordering as inbound messages so a contact is never split across two threads.

### Out-of-window session messages fail explicitly

Upstream v4.13 silently attempted a template send when the 24-hour window was closed even without template params; v4.16+ marks the message failed with a localized "outside messaging window" error instead. We port the new behavior (MIT) — it surfaces a real operator error instead of a confusing provider rejection.

## Risks / Trade-offs

- **Mixed-license change dir** -> The clean-room boundary is documented per item in this design and in the campaign spec header; implementers must not copy upstream enterprise expression while building `Pilot::CampaignRecipient`.
- **Contact identity churn** -> Identifier sync creates extra `contact_inboxes` rows per contact; uniqueness is enforced per (inbox, source_id) and races with concurrent webhooks are treated as no-ops.
- **Webhook status reconciliation ordering** -> Delivery/read/failed updates can arrive out of order or late; status regression must be ignored (needs-investigation marker left for terminal-state edge cases).
- **Feature-flag drift** -> WhatsApp campaigns remain behind `whatsapp_campaign`; seeds/docs must enable it or campaigns silently no-op.

## Migration Plan

1. Additive migrations first: campaign status/timestamps, channel health columns, `pilot_campaign_recipients`.
2. Port backend services/controllers behind existing routes + new namespaced routes.
3. Ship frontend pages (templates, campaign analytics, health, guided setup) once APIs are live.
4. Rollback: new columns/tables are additive and ignorable; new routes/UI can be removed without data loss. Recipient rows are informational only.

## Open Questions

- Should the analytics API be available for SMS one-off campaigns too, or WhatsApp-only as upstream? Spec assumes WhatsApp-only (needs investigation: upstream restricts the analytics controller to WhatsApp one-off campaigns; confirm desired Konversio scope).
- Does Konversio want the contact-info request template auto-configuration upstream added, or manual template selection only?
