# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.0.3] - 2026-10-02

**Full feature parity with Chatwoot v4.18.0.** This release ports every
user-facing capability from upstream releases v4.14 through v4.18 into
Konversio — over 180 changes across 26 feature areas. Because Konversio is
100% MIT, everything that upstream ships as paid Enterprise code (all of the
AI assistant work, audit logs, parts of WhatsApp campaigns and calling) was
rebuilt from scratch as open source under `Pilot::`.

### AI Assistant (Pilot)

- Conversation outcomes: every AI-handled conversation now records how it ended — resolved, handed off, or abandoned — with categorized handoff reasons.
- Agent sessions & citations: each AI run is recorded step by step, and answers can cite the exact knowledge sources they used, with trusted-URL checks.
- Knowledge auto-sync: connected documents re-sync on a schedule so the assistant never answers from stale content.
- Reply suggestions: agents get an AI-drafted reply they can edit and send, instead of writing from scratch.
- Playground: a test console to try assistant behavior safely before it talks to real customers.
- Response integrity: long answers are split into readable multi-part messages, trimmed to each channel's length limits, and the assistant asks for consent before handing off to a human.
- False-promise detection: the assistant can no longer promise things it can't do ("I'll email you the receipt") — replies are checked and rewritten or blocked, with a new dashboard toggle to control it.
- Audiences & lifecycle: target the assistant to specific customer audiences, set active hours/schedules, and define what happens when a customer goes quiet.
- AI assignment & controls: conversations can be assigned directly to the AI, and each scenario's tools can be switched on or off individually.
- FAQ suggestions: the assistant mines real conversations for recurring questions and drafts new FAQ entries for your team to review and approve.
- Assistant analytics: a new overview dashboard with resolution trends, drill-downs into individual conversations, and insight summaries.

### WhatsApp

- Campaign variables, one-off campaign status, and per-recipient delivery outcomes.
- BSUID support for messaging users without a phone number, including BSUID-only campaigns.
- Template management (create, sync, and edit) for both Cloud API and Twilio, directly in the app.
- Click-to-WhatsApp ad referral tracking and WhatsApp Flow form responses shown in the conversation.
- Account health and business profile visibility, plus a guided manual setup flow.
- Voice messages and WhatsApp calls, including coexistence with the WhatsApp Business app.

### Voice & Video Calling

- Voice calling: inbound calls, call joining, recordings, and live controls (mute, hold) from the dashboard.
- Call transcription via Pilot speech-to-text, and per-inbox call recording settings.
- Voice call dashboard and Twilio call-health monitoring with clearer outbound error reporting.
- Video calls migrated to Cloudflare RealtimeKit (replacing the retired Dyte SDK).

### Help Center

- New doc-style layout with a layout switcher, per-locale portal branding and settings, and category icons.
- Full-text search, bulk article actions, article reordering, and per-locale popular content.
- Staged edits: draft changes to published articles without taking the live version offline.
- AI-assisted article translation and category-based article creation.
- Video embeds, improved media uploads with previews, and per-portal analytics integrations.

### Reporting & Analytics

- Conversation and message drill-downs: click any report metric to see the exact conversations behind it.
- Faster reopen-rate calculation on large accounts.

### Conversations & Productivity

- Expanded chat list with attachment previews, quoted replies, and visible conversation IDs.
- Unread counts and badges in the sidebar, with smarter conversation ordering.
- Bulk actions on conversations, including bulk label removal from the right-click menu.
- Conversation history navigation and sorting in filtered views.
- Dedicated search results page, resizable table columns, and inline images in messages.
- Composer upgrades: run macros straight from the reply editor or command bar, plus searchable pickers for canned responses, mentions, variables, and emoji.

### Companies & Contacts

- Companies: create and manage companies with notes, labels, custom attributes, and a full activity history.
- Link contacts to companies, filter conversations by contact or company, and see contact media in one view.
- Call records are now preserved when merging contacts.

### Data Imports

- Import your existing data from Intercom (contacts, conversations, articles).
- Import from Freshdesk (contacts, tickets, replies, private notes), with retry-safe processing.

### Assignment & Automation

- Assignment policies can skip stale conversations when handing out work.
- Delayed automations with more conditions, so time-based rules fire exactly when intended.
- Fixed automation rules with multiple excluded labels, which previously matched the wrong conversations.

### Administration & Security

- Audit logs: filter, search, and sort every administrative action, including message deletions, with IP masking and location details.
- Super Admin: account suspension history, agent invitation limits, and per-account usage limits.
- Webhook validation and SSRF hardening, safer file uploads and CSV exports, and stricter HTML rendering.
- Sign-in and session hardening, widget identity verification with secret rotation, and inbox webhook rate limits.
- IMAP/SMTP authentication improvements and inbox identity verification.

### Onboarding & Setup

- A guided onboarding wizard with OAuth return flows and automatic email-provider detection.
- AI-generated Help Center starter content during setup.
- Guided manual WhatsApp setup for accounts without embedded signup.

### Platform

- Upgraded to Rails 7.2.
- Widget SDK is ~28% smaller, and the widget now speaks Uzbek, Slovenian, and Estonian.

## [0.0.2] - 2026-06-26

**Pilot's AI agents can now call your own backend APIs.** Custom tools let an
assistant reach any HTTP endpoint you define — an order lookup, an eligibility
check, any internal service — fetch live data, and answer from it. That turns
the bot from a docs-and-FAQ responder into an intelligent layer over your real
systems, and it reliably invokes the right tool when a question calls for it.

In 0.0.1 these tools could be configured but never actually worked against a
real (authenticated, HTTPS) endpoint. 0.0.2 makes them functional end to end —
verified live against a production API.

### Added

- Custom tools authenticate to their endpoint: Bearer token, Basic auth, or API key (header or query placement).
- Custom tool endpoint URLs support Liquid templating, e.g. `/nationality-check/{{ nationality }}`.
- `PILOT_TOOL_ALLOWED_HOSTS` — an explicit, per-host allowlist to let a custom tool reach a named internal or local endpoint past the SSRF guard.
- The Autopilot Playground shows which tools each answer used, and renders assistant replies as markdown.

### Fixed

- Custom tools now send their configured auth header — previously every authenticated endpoint returned 401.
- HTTPS custom tools behind a CDN / SNI virtual host (e.g. Cloudflare) now complete the TLS handshake (SNI uses the hostname, not the SSRF-resolved IP).
- The custom-tool enable/disable toggle persists instead of silently reverting on reload.
- Pilot reliably calls the relevant custom tool on every turn, including follow-up questions, instead of skipping it and answering from memory.
- The custom-tools dialog no longer blanks on a missing icon, and placeholder braces in examples render correctly.
- Playground send-button alignment.

### Changed

- Pilot autopilot temperature lowered to 0.3 for steadier tool use.
- Updated `markdown-it` 14.1.1 → 14.2.0 (the renderer behind assistant-message markdown).

### Security

- Updated `dompurify` 3.4.0 → 3.4.11, the HTML sanitizer that all rendered message content passes through.

## [0.0.1]

Initial Konversio release: a hard fork of Chatwoot v4.13.0 with the
`enterprise/` overlay and Captain AI removed and replaced by `Pilot::`,
Konversio's own open-source AI assistant (ai-agents SDK + RubyLLM).
100% MIT, self-hosted.
