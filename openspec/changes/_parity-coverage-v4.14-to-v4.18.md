# Parity coverage: Chatwoot v4.13.0 → v4.18.0

Master tracker for the openspec parity goal. Every changelog item from upstream
v4.14.0 through v4.18.0 maps to exactly one change directory in
`openspec/changes/` or to the exclusions list at the bottom.

Clean-room rule: change dirs prefixed `pilot-` (and any EE-origin item) are
specced from functional requirements only — no verbatim or reworded upstream
expression (prompts, copy, label taxonomies, regexes, file/class naming).
MIT-tree items may reference and port upstream code verbatim.

Status: pending / written / verified

## Change directories and covered items

| Change dir | License axis | Changelog items | Status |
|---|---|---|---|
| `companies-management` | mixed (EE nested controllers → requirements) | v4.14.0 Companies (creation, details, notes, history, labels, activity); v4.14.2 contact filter for conversations; v4.15.0 contact/company updates (media view, contact filters, company selector); v4.17.1 preserve call records on contact merge | written+validated |
| `help-center-revamp` | MIT | v4.14.1 doc-style layout + switcher; v4.14.2 HC search, per-locale portal branding, bulk article category changes; v4.15.0 new layout, per-locale settings, category icons, editor improvements; v4.16.0 staged edits, admin search, article reordering, popular content by locale; v4.14.0 bulk actions | written+validated |
| `help-center-rich-content` | mixed (AI translation EE → requirements) | v4.14.0 AI translation, URL embeds, category-based article creation; v4.17.0 analytics integrations and video embeds; v4.18.0 improved media uploads and previews | written+validated |
| `inbox-conversation-ux` | MIT | v4.14.0 expanded chat list, bulk actions, attachments, quoted replies, conversation IDs; v4.14.1 unread counts/sidebar ordering/badges, bulk label removal; v4.15.0 unread counts/badges/ordering/filter (final state per v4.15.1 revert of mention/participating/folder counts); v4.16.2 conversation label search in right-click menu; v4.18.0 conversation history navigation and sorting in filtered views | written+validated |
| `search-and-tables` | MIT | v4.14.2 resizable table columns, inline images in messages; v4.15.0 search results page, table resizing, inline images, message rendering | written+validated |
| `voice-calling` | mixed (per-inbox recording/transcription EE → requirements) | v4.14.0 voice groundwork, inbound calls, recordings, call join; v4.14.1 WhatsApp/Twilio Cloud Calling, voice-call UX; v4.14.2 WhatsApp voice messages, Twilio call controls; v4.15.0 calling updates, mute controls, inbox call settings; v4.16.0 WhatsApp Calls for non-embedded signup inboxes; v4.16.1 voice call dashboard; v4.16.2 WhatsApp health monitoring, outbound call errors; v4.17.0 Twilio call transcription; v4.18.0 per-inbox call recording/transcription settings | written+validated |
| `realtimekit-video-calls` | MIT (verbatim port of PR #14752) | v4.16.0 Dyte → Cloudflare RealtimeKit migration | written+validated |
| `whatsapp-platform` | mixed (campaign recipient tracking EE → requirements) | v4.14.0 WhatsApp campaign variables; v4.14.1 BSUID support; v4.14.2 one-off campaign processing status; v4.16.1 WhatsApp coexistence, phone lookup, reply-window; v4.17.0 template management (Cloud API + Twilio) in-app/API, campaign delivery/recipient outcomes, CTWA referrals, Flow responses; v4.17.1 account health, business profile; v4.18.0 guided setup, BSUID-only campaigns and calls | written+validated |
| `data-imports` | MIT | v4.16.0 Intercom import; v4.16.2 Intercom retry/reliability; v4.17.0 Freshdesk import (contacts, tickets, replies, private notes) | written+validated |
| `assignment-and-automation` | MIT | v4.16.0 assignment policies exclude stale conversations; v4.18.0 additional conditions for delayed automations; v4.17.1 automation filter comma fix | written+validated |
| `composer-productivity` | MIT | v4.17.0 macros from reply editor and command bar, canned response search/preview, mentions/variables/emoji search; v4.14.1 editor shortcuts fixes | written+validated |
| `channel-and-security-hardening` | MIT | v4.14.0 webhook validation, SSRF hardening, safer uploads, SAML fixes, admin auth checks, IMAP auth options; v4.14.1 SafeFetch, private inbox webhook allowlist, XML/PFX attachments, new inbox webhook events; v4.14.2 richer webhook payloads; v4.15.0 sessions, webhooks, OAuth, secrets fixes; v4.16.0 widget identity verification, agent bot access tokens, dashboard apps, inbox limits; v4.16.1 spam-protection gating (Public API + webhooks), rate limits, hook deletion, token access; v4.16.2 conversation participants, account/email limits; v4.17.0 uploads, account scoping, feature access, CSV exports; v4.18.0 sign-in, macros, webhooks, media, HTML rendering hardening, SMTP independent of IMAP, Slack alerts-only, inbox identity verification secret rotation | written+validated |
| `onboarding-and-setup` | mixed (EE Help Center generation → requirements) | v4.14.1/v4.14.2/v4.15.0 onboarding: Help Center generation + status, OAuth redirects/return flows, email provider detection; v4.18.0 guided WhatsApp setup | written+validated |
| `reporting-drilldowns` | MIT; reopen-rate fix found to be EE → specced clean-room | v4.16.0 conversation and message drilldowns for reports; v4.16.1 reopen-rate performance fix | written+validated |
| `platform-maintenance` | MIT | v4.17.0 Rails 7.2.3.1 (NOTE: Konversio already did its own Rails 7.2 migration — spec is reconcile/verify); v4.14.2 Puma/Vite/OAuth dependency updates; v4.16.0 Uzbek, v4.17.0 Slovenian, v4.18.0 Estonian widget locales; v4.17.1 SDK size reduction | written+validated |
| `super-admin-governance` | MIT | v4.16.2 Super Admin account suspension metadata, agent invitation limit; v4.16.1 agent quotas; v4.16.2 account limits | written+validated |
| `audit-log-governance` | EE → requirements | v4.17.0 filter/search/sort audit logs; v4.18.0 message deletion audits, IP masking, location details | written+validated |
| `pilot-conversation-outcomes` | EE → requirements (CLEAN-ROOM) | v4.17.0 Captain outcomes; episode-based outcome tracking, handoff reason categorization, lifecycle events | written+validated |
| `pilot-agent-sessions-and-citations` | EE → requirements (CLEAN-ROOM) | v4.17.1 Captain reasoning/context; agent session records, citations in responses, trusted citation URLs | written+validated |
| `pilot-faq-suggestions` | EE → requirements (CLEAN-ROOM) | v4.14.0 FAQ improvements; v4.16.2 FAQ suggestion review API and interface | written+validated |
| `pilot-audiences-and-lifecycle` | EE → requirements (CLEAN-ROOM) | v4.17.0 Captain audiences, schedules, inactivity handling, knowledge usage; v4.18.0 assignment, scenario and tool controls | written+validated |
| `pilot-assistant-analytics` | EE → requirements (CLEAN-ROOM) | v4.16.0 Captain assistant overview and drill-down analytics; v4.17.1 analytics improvements | written+validated |
| `pilot-playground` | EE → requirements (CLEAN-ROOM) | v4.18.0 improved playground testing | written+validated |
| `pilot-knowledge-auto-sync` | EE → requirements (CLEAN-ROOM) | v4.14.0 Captain document sync; document auto-sync service | written+validated |
| `pilot-reply-suggestion` | EE → requirements (CLEAN-ROOM) | Copilot reply-suggestion mode (v4.16–4.17 era) | written+validated |
| `pilot-response-integrity` | EE → requirements (CLEAN-ROOM) | multi-part responses with citations, channel-aware length limits, handoff consent protocol, false-promise detection (v4.16–4.18) | written+validated |

## Exclusions (with reasons)

| Item | Reason |
|---|---|
| Shopify billing path, `AccountBillingIdentity`, plan configuration, Stripe rework (v4.16–v4.17 EE billing) | Chatwoot-Cloud-only; Konversio is self-hosted only |
| Captain message reports (`captain_message_reports`, v4.16 EE) | Gated on `ChatwootApp.chatwoot_cloud?` — cloud-only feature |
| "Companies enabled for Business cloud plans" (v4.14.2) | Cloud plan gating; the Companies feature itself is specced in `companies-management` |
| Upstream Captain V1→V2 migration tooling (instruction classifier/auditor, draft appliers) | Migration tooling for upstream's legacy V1 deployments; Konversio's Pilot has no V1 legacy to migrate |
| Generic "reliability fixes / numerous bug fixes" lines (all releases) | Fixes to shared existing code are selective-backport candidates, not spec'd features; tracked separately |
| Dependency bumps with no user-facing change (beyond those in `platform-maintenance`) | Routine maintenance, not a capability |
| SAML fixes (v4.14.0 "Security: … SAML fixes") | Live entirely in upstream `enterprise/` (EE) and Konversio ships no SAML; functional takeaways recorded in `channel-and-security-hardening/design.md` should SAML ever be introduced |
| Voice calling backend orchestration (v4.14–v4.16 voice items) | Discovered during spec-writing to live entirely in upstream `enterprise/` (EE) despite changelog tagging; `voice-calling` specs it clean-room as original backend code — only frontend/migrations/health-service are MIT ports |

## Post-writing verification (2026-10-01)

- All 26 change directories contain proposal.md, design.md, tasks.md, and at least one specs/*/spec.md.
- `openspec validate <change>` passes for all 26 (only warning: tasks-checkbox counting, identical on the repo's pre-existing reference changes).
- Clean-room check: no upstream handoff-taxonomy strings, no "Captain" references, and no `enterprise/` paths appear in any EE-derived `specs/**/spec.md` file.
- Spec-writers left `needs investigation` markers in individual design.md/spec.md files — grep for "needs investigation" before implementation planning.
- Two agents independently flagged a latent XSS: Konversio's `lib/custom_markdown_renderer.rb` does not HTML-escape embed captures (upstream fixed this by v4.18.0) — covered by a task in `help-center-rich-content` / `channel-and-security-hardening`.
