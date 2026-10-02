# Parity coverage: Chatwoot v4.13.0 → v4.18.0

Master tracker for the openspec parity goal. Every changelog item from upstream
v4.14.0 through v4.18.0 maps to exactly one change directory in
`openspec/changes/` or to the exclusions list at the bottom.

Clean-room rule: change dirs prefixed `pilot-` (and any EE-origin item) are
specced from functional requirements only — no verbatim or reworded upstream
expression (prompts, copy, label taxonomies, regexes, file/class naming).
MIT-tree items may reference and port upstream code verbatim.

Status: pending / written / validated / implemented

## Change directories and covered items

| Change dir | License axis | Changelog items | Status |
|---|---|---|---|
| `companies-management` | mixed (EE nested controllers → requirements) | v4.14.0 Companies (creation, details, notes, history, labels, activity); v4.14.2 contact filter for conversations; v4.15.0 contact/company updates (media view, contact filters, company selector); v4.17.1 preserve call records on contact merge | merged to main |
| `help-center-revamp` | MIT | v4.14.1 doc-style layout + switcher; v4.14.2 HC search, per-locale portal branding, bulk article category changes; v4.15.0 new layout, per-locale settings, category icons, editor improvements; v4.16.0 staged edits, admin search, article reordering, popular content by locale; v4.14.0 bulk actions | merged to main |
| `help-center-rich-content` | mixed (AI translation EE → requirements) | v4.14.0 AI translation, URL embeds, category-based article creation; v4.17.0 analytics integrations and video embeds; v4.18.0 improved media uploads and previews | merged to main |
| `inbox-conversation-ux` | MIT | v4.14.0 expanded chat list, bulk actions, attachments, quoted replies, conversation IDs; v4.14.1 unread counts/sidebar ordering/badges, bulk label removal; v4.15.0 unread counts/badges/ordering/filter (final state per v4.15.1 revert of mention/participating/folder counts); v4.16.2 conversation label search in right-click menu; v4.18.0 conversation history navigation and sorting in filtered views | merged to main |
| `search-and-tables` | MIT | v4.14.2 resizable table columns, inline images in messages; v4.15.0 search results page, table resizing, inline images, message rendering | merged to main |
| `voice-calling` | mixed (per-inbox recording/transcription EE → requirements) | v4.14.0 voice groundwork, inbound calls, recordings, call join; v4.14.1 WhatsApp/Twilio Cloud Calling, voice-call UX; v4.14.2 WhatsApp voice messages, Twilio call controls; v4.15.0 calling updates, mute controls, inbox call settings; v4.16.0 WhatsApp Calls for non-embedded signup inboxes; v4.16.1 voice call dashboard; v4.16.2 WhatsApp health monitoring, outbound call errors; v4.17.0 Twilio call transcription; v4.18.0 per-inbox call recording/transcription settings | merged to main |
| `realtimekit-video-calls` | MIT (verbatim port of PR #14752) | v4.16.0 Dyte → Cloudflare RealtimeKit migration | implemented (merged to main @ 90673ffee) |
| `whatsapp-platform` | mixed (campaign recipient tracking EE → requirements) | v4.14.0 WhatsApp campaign variables; v4.14.1 BSUID support; v4.14.2 one-off campaign processing status; v4.16.1 WhatsApp coexistence, phone lookup, reply-window; v4.17.0 template management (Cloud API + Twilio) in-app/API, campaign delivery/recipient outcomes, CTWA referrals, Flow responses; v4.17.1 account health, business profile; v4.18.0 guided setup, BSUID-only campaigns and calls | merged to main |
| `data-imports` | MIT | v4.16.0 Intercom import; v4.16.2 Intercom retry/reliability; v4.17.0 Freshdesk import (contacts, tickets, replies, private notes) | merged to main |
| `assignment-and-automation` | MIT | v4.16.0 assignment policies exclude stale conversations; v4.18.0 additional conditions for delayed automations; v4.17.1 automation filter comma fix | merged to main |
| `composer-productivity` | MIT | v4.17.0 macros from reply editor and command bar, canned response search/preview, mentions/variables/emoji search; v4.14.1 editor shortcuts fixes | merged to main |
| `channel-and-security-hardening` | MIT | v4.14.0 webhook validation, SSRF hardening, safer uploads, SAML fixes, admin auth checks, IMAP auth options; v4.14.1 SafeFetch, private inbox webhook allowlist, XML/PFX attachments, new inbox webhook events; v4.14.2 richer webhook payloads; v4.15.0 sessions, webhooks, OAuth, secrets fixes; v4.16.0 widget identity verification, agent bot access tokens, dashboard apps, inbox limits; v4.16.1 spam-protection gating (Public API + webhooks), rate limits, hook deletion, token access; v4.16.2 conversation participants, account/email limits; v4.17.0 uploads, account scoping, feature access, CSV exports; v4.18.0 sign-in, macros, webhooks, media, HTML rendering hardening, SMTP independent of IMAP, Slack alerts-only, inbox identity verification secret rotation | implemented (merged to main @ 90673ffee) |
| `onboarding-and-setup` | mixed (EE Help Center generation → requirements) | v4.14.1/v4.14.2/v4.15.0 onboarding: Help Center generation + status, OAuth redirects/return flows, email provider detection; v4.18.0 guided WhatsApp setup | merged to main |
| `reporting-drilldowns` | MIT; reopen-rate fix found to be EE → specced clean-room | v4.16.0 conversation and message drilldowns for reports; v4.16.1 reopen-rate performance fix | merged to main |
| `platform-maintenance` | MIT | v4.17.0 Rails 7.2.3.1 (NOTE: Konversio already did its own Rails 7.2 migration — spec is reconcile/verify); v4.14.2 Puma/Vite/OAuth dependency updates; v4.16.0 Uzbek, v4.17.0 Slovenian, v4.18.0 Estonian widget locales; v4.17.1 SDK size reduction | implemented (merged to main @ 90673ffee) |
| `super-admin-governance` | MIT | v4.16.2 Super Admin account suspension metadata, agent invitation limit; v4.16.1 agent quotas; v4.16.2 account limits | merged to main |
| `audit-log-governance` | EE → requirements | v4.17.0 filter/search/sort audit logs; v4.18.0 message deletion audits, IP masking, location details | merged to main |
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

## Implementation log

### Phase 0 — merged to `main` @ 90673ffee

- `realtimekit-video-calls` — full upstream PR #14752 port (19/20 tasks; live-credential smoke test outstanding).
- `platform-maintenance` — puma/oauth security bumps, rails-i18n, widget SDK −28% gzip, uz/sl/et locales.
- `channel-and-security-hardening` — SafeFetch, webhook hardening, uploads/CSV/markdown sanitization (includes the latent XSS fix), IMAP/SMTP auth, widget identity rotation, sessions/sign-in hardening, rack-attack throttles, agent/inbox limits, suspension metadata.

### Phase 1 — merged to `main`

Worktrees bootstrapped with a real `pnpm install` (no `node_modules` symlink) and per-worktree isolated test DB + Redis to allow parallel agents. Merge commits: `d3f55b706` (reporting-drilldowns), `4d94416f1` (inbox-conversation-ux), `bca23ee86` (search-and-tables), `96303fc87` (composer-productivity), `b716c97e0` (help-center-revamp).

Two conflicts were resolved at merge: `WootWriter/Editor.vue` (both branches registered `useKeyboardEvents` for Alt+P/Alt+L — kept one block with composer's `allowOnFocusedInput: false` plus search-and-tables' `$mod+Shift+KeyV`) and `lib/konversio_markdown_renderer.rb` (both branches independently reworked article table column widths — took revamp's superset implementation; search-and-tables' shared `MarkdownTableColumnWidths` module remains used by `custom_markdown_renderer.rb`).

Coordinator verification on merged `main`: rubocop 91 files 0 offenses; eslint 0 errors; rspec 549/0; full vitest 3622/0 — after updating 3 stale specs the merge exposed (`api/specs/contacts`, `helper/specs/uploadHelper`, `store/modules/specs/contactConversations/actions`; commit `1a88df755`).

- `reporting-drilldowns` (`feat/reporting-drilldowns`) — commits `4eb987075`, `5589b3ab7`, `20dc868ea`. Admin-only v2 report drilldown API + drawer; metric registry, timestamp validator, builder, serializer, throttle. rspec 48/0; ported vitest green; rubocop/eslint clean. Tasks 1–14 done; **task 15 manual smoke deferred** (no live instance); **task 16 dormant** clean-room requirements left unimplemented.
- `inbox-conversation-ux` (`feat/inbox-conversation-ux`) — commits `08a394c15`, `bfecf62fc`. Unread-count services/endpoint/ActionCable, sidebar badges + sorting, expanded chat list, bulk actions, context-menu label search, quoted replies, shared files, history nav, filtered sorting. rspec 132/0, vitest 203/0, rubocop/eslint clean. Notes: Konversio uses **JSONB feature flags (not the full bitset the design assumed)** so the two migrations were re-dated rather than repurposing slots; **task 9 shipped expanded cards *without* the upstream `ConversationList.vue` extraction** (Konversio's `ChatList` carries Pilot lifecycle customizations); 3 pre-existing `filter_service_spec` failures confirmed on base.
- `search-and-tables` (`feat/search-and-tables`) — commits `23aca5c52`, `0e87a1c49`, `41d9d892a`, `817ee23b2`, `0a0d341f2`. Deterministic search ordering, exact timestamps, pagination, fallback attachment bubble, editor inline images + resizable table columns, portal column widths. rspec 86/0, vitest 129/0, rubocop/eslint clean. Notes: shared portal render logic landed in `lib/markdown_table_column_widths.rb` (consumed by both `custom_markdown_renderer` and `konversio_markdown_renderer`); fixed a pre-existing `useExactTimestamp` cache-key bug.
- `composer-productivity` (`feat/composer-productivity`) — commits `6bf957653`, `026e1e20e`, `92828e5d5`. Macro execution + rebuilt inline pickers (macros, canned responses, mentions, variables, emoji), command-bar macros, cleanup. Full vitest 3408/0; eslint clean. Notes: added `prosemirror-inputrules` directly (fork's pinned schema bundle does not re-export `InputRule`); **skipped upstream `ReplyBox.spec.js`** as misfiled (tests an unrelated Instagram composer-restriction feature).
- `help-center-revamp` (`feat/help-center-revamp`) — commits `58d4ee279`, `2e504e1a0`, `0673dceb2`, `a7897ea57`, `ec488d2ec`. Portal config schema, per-locale settings, doc-style + classic layouts, search, bulk actions, reorder, staged edits, category icon picker. rspec 233/0, full vitest 3409/0, rubocop/eslint clean. Notes: **task 24 (shared ProseMirror editor foundation) deferred to `help-center-rich-content`**; kept Turbolinks (Konversio has no `@hotwired/turbo-rails`); analytics + bulk translate intentionally omitted per design.

- `help-center-rich-content` (`feat/help-center-rich-content`, commits `096715c31`…`50d57d6b1`, fast-forwarded to `main`) — bulk AI article translation (clean-room, core-tree `Pilot::`, gated by `pilot_tasks`), per-portal analytics integrations, category-scoped article creation, editor video embeds + upload pipeline (progress/abort/pending-upload guards). It also fixed a real XSS hole: embed-capture escaping existed only in the now-dead `CustomMarkdownRenderer`, not in the active `KonversioMarkdownRenderer`. rspec 141/0; full vitest 3651/0; rubocop/eslint clean. Task 29 manual smoke deferred; article description intentionally reused untranslated (upstream parity); no CSP change needed (fork's CSP initializer is commented out).

### Phase 2 — merged to `main`

8 change dirs, implemented in two swarms (5 + 3) and merged. Merge conflicts resolved: `config/features.yml` (flag unions), `db/schema.rb` (`version:` line set to the max migration timestamp — the auto-merged body was kept; do NOT run `db:migrate` from scratch, the fork's 2023 `add_cached_labels_list` migration fails and `schema:dump` would clobber the file), `advancedFilters.json` (key union), and the WhatsApp/voice service overlaps (delegated resolution: single coherent method definitions; duplicate migration timestamps renumbered `20261002000014`/`20261002000015`; a duplicate `COEXISTENCE_FINISH_EVENT` block and a duplicate `add_phone_number_health` migration removed).

Coordinator verification on merged `main`: rubocop 375 files 0 offenses; eslint 0 errors; rspec 1457/0 (1 expected pending); full vitest 390 files / 3820 tests, 0 failures.

- `whatsapp-platform` (`feat/whatsapp-platform`, merge `67916e7ff`) — BSUID identity, contact-info requests, template sync + settings, campaign recipient tracking + analytics (clean-room `Pilot::CampaignRecipient`), account health/business profile, guided manual setup, referral/Flow bubbles. rspec 702/0, full vitest 3682/0. Task 15 skipped (no Konversio call subsystem at the time), task 17 Twilio health deferred, task 30 manual smoke deferred; conversation-payload `contact_info_request` left hardcoded `available: false` per upstream.
- `voice-calling` (`feat/voice-calling`, merge `112a05cd3`) — `Call` domain, Twilio adapter/conference/recording, Pilot speech-to-text, WhatsApp calls, call UI/history, inbox call settings + Twilio health. rspec 84/0, full vitest 3685/0. Task 38 manual smoke deferred.
- `data-imports` (`feat/data-imports`) — provider-agnostic import framework (Intercom, Freshdesk) + settings UI. rspec 233/0, full vitest 3667/0. Tasks 24–25 live-provider smoke deferred; `data_import` flag enabled.
- `assignment-and-automation` (`feat/assignment-and-automation`) — stale-assignment exclusion, delayed automations + pending-execution job, comma-safe multi-value input. rspec 150/0, full vitest 3673/0. Task 18 deferred. Open: multi-label `not_equal_to` skip needs the separate v4.18 `FilterService` label-query refactor (explicit non-goal); policy-less inboxes now get the 168h default.
- `companies-management` (`feat/companies-management`) — core-tree companies backend (list/detail/notes/history/labels/activity), contact↔company association, company filter, dashboard UI. rspec 159/0, full vitest 3647/0. Task 13 (contact-merge call reassignment) blocked on the calls capability; task 26 manual. Reserved-domain exclusion added to `BusinessEmailDetectorService` (fixture-safety).
- `super-admin-governance` (`feat/super-admin-governance`) — model-level inbox limit, agent quota 402s, suspension history, channel-controller rescues. rspec 229/0. Most tasks pre-existed on base; kept the fork's no-cloud-gate email-capacity behavior.
- `audit-log-governance` (`feat/audit-log-governance`, EE → clean-room) — core `AuditLog` model, admin listing API, IP masking + GeoIP enrichment jobs, filterable settings UI. rspec 56/0 (+regressions), full vitest 3670/0. GeoIP best-effort (MaxMind DB not provisioned).
- `onboarding-and-setup` (`feat/onboarding-and-setup`) — onboarding wizard, enrichment, OAuth return flows, WhatsApp manual setup, account health, clean-room `Pilot::` Help Center generation. rspec 467/0, full vitest 3708/0. Task 24 manual smoke skipped; scraper provider vendor-neutral via env config.

### Not yet started

- Phase 3: the nine clean-room `pilot-*` change dirs (conversation outcomes, agent sessions & citations, FAQ suggestions, audiences & lifecycle, assistant analytics, playground, knowledge auto-sync, reply suggestion, response integrity).
