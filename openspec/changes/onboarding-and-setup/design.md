## Context

Upstream shipped a new dashboard onboarding wizard and a series of setup-assistance improvements between v4.14.0 and v4.18.0. Konversio forked at v4.13.0 and has none of it. This change covers the onboarding/setup slice of that delta:

- **v4.14.1**: onboarding improvements for Help Center generation and email detection
- **v4.14.2**: onboarding OAuth return flows and Help Center generation status
- **v4.15.0**: onboarding OAuth redirects and email provider detection
- **v4.18.0**: guided WhatsApp setup and clearer account health

**Scope note on the base wizard.** The two-step onboarding wizard itself (account-details form, step cursor, web widget provisioning) was introduced upstream in the v4.14.0 cycle without a distinct changelog line, and the parity coverage tracker assigns all onboarding work to this change directory. It is therefore specced here at minimal level as `onboarding-step-flow`, because every assigned item hooks into it. If the coordinator assigns the base wizard elsewhere, that spec can be lifted out unchanged.

**License axis per sub-item:**

| Sub-item | Axis | Treatment |
|---|---|---|
| Onboarding step flow, web widget provisioning | MIT | Reference/port upstream `app/controllers/api/v1/accounts/onboardings_controller.rb`, `app/services/onboarding/web_widget_creation_service.rb`, `app/javascript/dashboard/routes/dashboard/onboarding/**` |
| Email/social/channel detection (`WebsiteBrandingService`, `SocialLinkParser`, `Account::BrandingEnrichmentJob`, detected-channel composables) | MIT | Reference/port upstream core files directly; verbatim porting is legal (MIT) |
| OAuth return flows (`OauthAuthorizationController`, `OauthCallbackController`, Instagram/TikTok callbacks + integration helpers) | MIT | Reference/port upstream core files directly |
| Guided WhatsApp setup + webhook verification (`Whatsapp::ManualSetupController`, validation/setup/status services, wizard UI) | MIT | Reference/port upstream core files directly |
| WhatsApp account health (`Whatsapp::HealthService` persistence, health sync jobs, `InboxHealthManagement` concern, health UI) | MIT | Reference/port upstream core files directly |
| Help Center generation (LLM article writer, generation status) | **EE → requirements (clean-room)** | Upstream `enterprise/` code was read for understanding only. The spec expresses behavior, state machines, and API contracts in original wording, targeting `Pilot::` services in the core tree. No upstream prompt text, UI copy, skip-reason strings, or file/class naming is carried over. |

The upstream Enterprise implementation depends on two EE-only pieces Konversio does not have: the Firecrawl client (`enterprise/app/services/firecrawl/`) for URL discovery/scraping, and `Captain::Llm::*` services for curation and writing. The clean-room spec replaces both with Konversio-native abstractions: a configurable web scraping provider and `Pilot::` LLM task services built on the existing `Pilot::BaseTaskService` pattern (`lib/pilot/`).

## Goals / Non-Goals

**Goals:**

- Bring the assigned v4.14.1/v4.14.2/v4.15.0 onboarding items and the v4.18.0 WhatsApp setup/health items to functional parity in Konversio.
- Run the full onboarding flow (including inbox setup and Help Center generation) on self-hosted installations — Konversio has no cloud/self-hosted split.
- Express the Help Center generation feature as functional requirements against `Pilot::` services, reusable with any configured LLM provider and scraping provider.
- Keep every asynchronous setup step (widget creation, enrichment, Help Center generation, WhatsApp webhook verification) observable in the UI and terminally resolvable — nothing may wedge in a "working" state forever.

**Non-Goals:**

- Account-enrichment via third-party brand APIs (upstream's EE context.dev integration) — out of scope; the MIT website scrape is the enrichment source.
- Enabling Gmail/Outlook OAuth connects inside the onboarding inbox-setup step (upstream deliberately defers these to in-app setup; detected email providers are shown as suggestions only).
- WhatsApp embedded signup changes, coexistence, calling, and template management — covered by `whatsapp-platform` and `voice-calling` change dirs.
- WhatsApp health monitoring items from v4.16.2/v4.17.1 beyond what the v4.18.0 "clearer account health" delta requires (overlap with `whatsapp-platform` is acknowledged; the health spec here targets the v4.18.0 surface).
- Onboarding analytics event taxonomy beyond noting that step visits/completions are tracked.

## Decisions

### Spec the base onboarding wizard minimally, and run it on self-hosted

Konversio needs the `onboarding_step` cursor (`account_details` → `inbox_setup`) and the `PATCH /api/v1/accounts/:account_id/onboarding` endpoint as the anchor for every other item. Upstream gates the `inbox_setup` step (and thus web widget provisioning, channel suggestions, and Help Center generation) behind `ChatwootApp.chatwoot_cloud?`; self-hosted instances finish onboarding after account details. Konversio is self-hosted only, so the spec drops the deployment gate: every installation runs both steps.

Alternatives considered:
- Keep upstream's cloud gate and only port the MIT mechanics. Then nothing in this change would ever be user-visible on a Konversio installation — the parity items would be dead code.
- Skip the base wizard and spec only the deltas against an assumed wizard. The deltas are meaningless without the anchor, and no other change dir owns the wizard.

Rationale: parity value is the working flow, not the deployment gating. The step cursor remains server-owned (the client declares the step it completes; the controller only acts when the stored cursor still points at that step), preserving upstream's idempotency and replay-safety properties.

### Port MIT mechanics verbatim where possible

The MX-record email provider inference, social-link extraction, enrichment job, OAuth state signing, WhatsApp validation/setup/health services, and the onboarding/manual-setup UI live in upstream's MIT core tree. Verbatim porting is legal and minimizes divergence risk; the specs cite the upstream files as the reference implementation. Brand strings are adjusted per the repo's rebranding guidance (`replaceInstallationName`, Konversio naming in user-facing copy).

Alternatives considered: re-expressing the MIT items at requirements level too. That would add clean-room cost with no legal benefit and would lose the reference-implementation link that makes the tasks concrete.

### Clean-room the Help Center generation against `Pilot::`

The generation pipeline is specced as behavior only: a portal bootstrap step, a planning step (discover candidate content URLs → LLM-proposed category/article plan → persist categories), a per-article writing step (scrape sources → LLM rewrite → draft article), and a durable generation-state tracker with a polled status API. New code lands in the core tree under `Pilot::` (e.g. `lib/pilot/help_center_*` services following `Pilot::BaseTaskService`, `app/jobs/pilot/` jobs); no `enterprise/` paths, no `Captain` naming, no upstream copy, prompts, or skip-reason strings.

Alternatives considered:
- Skip the feature as EE. Rejected: it is an assigned parity item and Konversio's policy is to re-express EE features as requirements, not to drop them.
- Reuse the upstream service names for familiarity. Rejected: names tied to the EE implementation are exactly what the clean-room rule excludes; `Pilot::` naming also matches Konversio's existing AI layer.

Rationale: the feature is a pipeline of well-understood steps; the requirements (discovery bound, minimum article threshold, terminal-state guarantee, draft-only output, source-URL provenance in article meta) capture everything user-observable without borrowing expression.

### Abstract the scraping provider

The spec requires "a configured web scraping provider" with two operations — discover content URLs on a domain, and scrape pages to markdown — without naming a vendor. If no provider is configured, Help Center generation reaches a terminal skipped state and onboarding continues normally.

Alternatives considered: hard-coding a specific scraping vendor (upstream uses Firecrawl, an EE dependency in their tree). Vendor lock-in would burden self-hosters and tie the spec to upstream's choice.

Rationale: Konversio operators should be able to point at any compatible scraping endpoint. needs investigation: which scraping provider(s) Konversio will officially support (self-hosted-friendly options, configuration keys, and endpoint contract) — to be settled at implementation time, not in this spec.

### Carry the OAuth return hint in the signed state payload

The `return_to: 'onboarding'` hint travels inside the OAuth `state` parameter, which is already a tamper-proof signed value in every flow: a signed global ID with a distinct purpose for Google/Microsoft (`OauthCallbackController`), and a signed JWT claim for Instagram/TikTok. Callbacks that resolve the onboarding hint redirect to the onboarding inbox-setup page; all other callers keep byte-identical behavior (settings page for existing channels, agents page for new ones).

Alternatives considered: a separate unsigned query parameter or a server-side session flag. Both are weaker — forgeable or lost across the OAuth round trip.

Rationale: reusing the existing signed state keeps the hint unforgeable and leaves non-onboarding flows untouched.

### Persist WhatsApp health on the channel, refresh on a schedule

Health is fetched from the Meta Graph API (phone number + business account fields), persisted on `channel_whatsapp` (`phone_number_health` JSON snapshot, checked-at timestamp, last error), and refreshed by a scheduler job for cloud-API channels on active accounts whose snapshot is stale (> 6 hours), oldest first, within the existing bulk external-call limit. The inbox `health` endpoint syncs on demand and returns the fresh snapshot including business profile; API authorization failures are surfaced distinctly so the UI can prompt reauthorization.

Alternatives considered: fetch-only, no persistence (every settings page load hits Meta — slow, rate-limit unfriendly, and loses the "last known good" snapshot when Meta errors); full history table (no consumer for history exists yet).

Rationale: a snapshot plus scheduled refresh gives the settings UI instant loads, keeps a degraded-but-informative state on provider errors, and bounds Meta API usage.

## Risks / Trade-offs

- **Base-wizard scope** -> Flagged to the coordinator; the `onboarding-step-flow` spec is deliberately minimal and self-contained so it can be moved if another change dir claims the wizard.
- **Scraping provider is unresolved** -> `needs investigation` marker in the Help Center generation spec; the spec's provider abstraction keeps this from blocking everything else.
- **Self-hosters without LLM or scraping config** -> Both are soft dependencies: generation reaches a terminal skipped state and onboarding completes normally; the status UI hides itself when generation never started or was skipped.
- **Health sync costs** -> The scheduler is limited to stale cloud-API channels on active accounts, oldest-first, under the existing bulk external HTTP limit.
- **OAuth state purpose is a contract** -> Adding the onboarding purpose must not alter existing signed-state consumers; specs require byte-identical behavior for non-onboarding callers.

## Open Questions

- Should the inbox-setup step remain skippable when zero channels are configured on a bare self-hosted install (upstream keeps Telegram/LINE as credential-free defaults)? Current spec: yes, skip always completes onboarding.
- Which web scraping provider(s) does Konversio support for Help Center generation, and under which installation config keys? (See needs-investigation marker.)
- Does the coordinator confirm `onboarding-step-flow` belongs in this change dir?
