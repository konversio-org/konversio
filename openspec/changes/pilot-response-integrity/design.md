## Context

Upstream Chatwoot shipped this feature set in its Enterprise tier across the v4.16–v4.18 line: a structured response schema with ordered parts and per-part citation indexes (`enterprise/lib/captain/response_schema.rb`), a channel-aware length table with conversation-type and provider-medium overrides (`enterprise/lib/captain/message_length_limit.rb`), a single-turn shortening pass with part/citation preservation and a hard failure when the reply still exceeds the budget (`enterprise/app/services/captain/assistant/response_rewriter.rb`, `enterprise/app/services/captain/assistant/agent_run_response.rb`), a consent-first handoff protocol plus a no-future-promises rule in the assistant's core behavioral rules (`enterprise/lib/captain/prompts/snippets/core_rules.liquid`, consulted for requirements only), a false-promise detection harness with repair-and-reverify semantics and a fail-safe handoff (`enterprise/app/jobs/captain/conversation/v1_false_promise_handler.rb`, `enterprise/app/services/captain/llm/assistant_false_promise_service.rb`), and a reduction of the agent loop's max-turns budget from 100 to 10 (`enterprise/app/services/captain/assistant/agent_runner_service.rb`).

**License axis: EE → requirements-level clean-room, for every item in this change.** All upstream reference material above is Enterprise-edition code. It was consulted for understanding only. Everything here is specified as functional requirements in original wording and must be implemented from this spec, not ported. In particular, the implementation must not copy or lightly reword upstream prompt text, UI copy, label/reason-category taxonomies, regexes, or internal class/file naming. Consistent with the standing IP-audit guidance, the result is characterized as an independently re-expressed capability of Konversio's Pilot AI layer.

Konversio-side anchors (all core tree, MIT):

- The autopilot pipeline is `Pilot::AutopilotInferenceJob` → `Custom::Pilot::AutopilotService` (`app/jobs/pilot/autopilot_inference_job.rb`, `custom/app/services/custom/pilot/autopilot_service.rb`). It runs the ai-agents SDK runner and today extracts a plain-string reply (`extract_reply`), parses handoff/resolution intent from sentinel tokens via `Custom::Pilot::HandoverEvaluator`, and executes handoffs through `Custom::Pilot::HandoffService`. This differs structurally from upstream's pipeline — hook points must be mapped, not assumed.
- `Custom::Pilot::AutopilotService` already exposes a configurable turn budget (`PILOT_AUTOPILOT_MAX_TURNS`, default 6) and already assembles the assistant's behavioral instructions from persona, guidelines, guardrails, and handoff-policy sections — the natural home for budget disclosure and the consent protocol.
- The sibling change `pilot-agent-sessions-and-citations` specifies the structured-reply value object (`lib/pilot/structured_reply.rb`), trusted citation-URL resolution, numbered-link rendering, and persistence of parts on the message. This change builds on that mechanism and specs the runner-side contract and the integrity constraints that interact with it (length measurement includes citation markup; the rewrite pass must preserve parts and citations).
- `Pilot::Assistant` already carries citation config (`feature_citation`, `citation_behavior`) on `pilot_assistants.config`.
- All channel classes referenced by the budget table exist in the core tree (`app/models/channel/`: `facebook_page`, `instagram`, `line`, `sms`, `telegram`, `tiktok`, `twilio_sms` with an `sms`/`whatsapp` medium enum, `whatsapp`, …).
- Account-level boolean settings live in `Account#settings` via `store_accessor` and are whitelisted in `app/models/concerns/account_settings_schema.rb`.
- Konversio has no credit/billing metering and no `enterprise/` directory; nothing in this change requires new DB tables.

## Goals / Non-Goals

**Goals:**

- Deliver AI replies that fit the destination channel's character budget, or no AI reply at all (fail safe to a human handoff) — never an oversized or silently truncated message.
- Give the model the length budget at generation time so the common case never needs the rewrite path.
- Keep citation integrity through every transformation: shortening must not change part count, part order, or citation assignment.
- Encode a consent-first handoff protocol and a no-unkeepable-promises rule in the assistant's behavioral contract, written in fresh Konversio wording.
- Add an opt-in, failure-isolated false-promise guard with repair-once, re-verify, and fail-safe-to-handoff semantics.
- Bound the agent loop with a conservative, safely configurable turn budget and defined exhaustion behavior.

**Non-Goals:**

- Changing how handoffs are executed (`HandoffService`, `bot_handoff!`, out-of-office templates) — only the decision contract and the guard-triggered path are in scope.
- Replacing Konversio's sentinel-token handoff/resolution parsing with upstream's tool-call-based mechanism.
- Streaming or splitting one AI reply into multiple channel messages; parts assemble into one outgoing message.
- Detection of other reply-quality problems (hallucination grounding, tone, PII) — only unsupported future-work promises.
- Applying the guard to copilot/agent-facing suggestions; it guards customer-facing autopilot replies.
- New persistence: no new tables; state rides on account settings and message `additional_attributes`.

## Decisions

### Extend the sibling structured-reply mechanism rather than defining a second one

The runner output contract (reasoning plus ordered parts with per-part source indexes), parsing/normalization, degradation to a single plain part, and persistence are specced here; trusted-URL resolution and numbered-link rendering remain owned by the `pilot-response-citations` capability in `pilot-agent-sessions-and-citations`. The two specs are written to be consistent.

Alternatives considered:

- Spec the whole citations stack again here. Duplicates the sibling spec and invites drift.
- Skip structured replies entirely and keep plain text. Forfeits per-part citations and makes precise length measurement impossible (citation markup length could not be separated from text length).

Rationale: one mechanism, one owner per concern.

### Length budget resolved per conversation, disclosed at generation, enforced post-generation

Budget resolution order: (1) conversation-type override (Instagram direct-message conversations), (2) provider-medium override (Twilio SMS vs Twilio WhatsApp), (3) per-channel-type table, (4) a generous default for channels without a tighter platform constraint. The numeric budgets are functional requirements derived from downstream platform limits, not copied expression.

Enforcement measures the fully rendered customer message — text plus citation link markup — against the budget. On overflow, exactly one shortening pass runs (single-turn, deterministic settings), instructed to preserve part count, order, citation assignment, and all factual content. The result is re-measured; still-over-budget (or a rewrite that violated the preservation invariants) fails the response. If citation markup alone exceeds the budget, no rewrite is attempted — the response fails immediately.

Alternatives considered:

- Truncate to the budget. Produces broken markdown and mid-sentence endings; unacceptable customer experience.
- Split into multiple messages. Changes delivery semantics per channel and is a much larger change; deferred.
- Rewrite repeatedly until it fits. Unbounded cost and latency; one pass plus fail-safe is predictable.

Rationale: rewrite-or-fail keeps the customer-facing guarantee absolute while keeping the failure path (human handoff) already established.

### Consent-first handoff protocol as prompt-level behavioral rules, enforced where deterministic hooks exist

The protocol is expressed as requirements on the assistant's instruction assembly (`handover_policy` and siblings in `Custom::Pilot::AutopilotService`), written in fresh wording: execute a handoff only on explicit customer request, accepted offer, or a guideline/guardrail-mandated transfer; offer only when the customer is blocked or the request exceeds capability; never claim a transfer that the handoff mechanism did not execute; never re-offer while a handoff is pending (Konversio already tracks a pending-handoff conversation state).

Alternatives considered:

- A post-generation classifier that blocks non-consented handoffs (upstream's V1 action-classifier approach). Adds an LLM call per reply for a problem Konversio's sentinel-token design already constrains: the model can only trigger a real handoff by emitting the sentinel, and the evaluator also matches explicit customer phrasing. Prompt-level consent plus the existing deterministic evaluator is proportionate; a classifier can be added later if field data shows violations.
- Hard-code consent in the evaluator (require a customer-phrase match before honoring the sentinel). Rejected: guideline-mandated transfers must be able to fire without a customer request.

Rationale: proportionate enforcement that respects Konversio's existing architecture.

### False-promise guard as an opt-in, failure-isolated post-generation step

A new account-level boolean setting (proposed `pilot_false_promise_guard_enabled`, whitelisted in `account_settings_schema.rb`) gates the guard. When enabled, after a draft reply is generated and before delivery — and skipped when the run already requested a handoff — a separate, deterministic detector call classifies the draft against the conversation context into exactly two outcomes: safe to deliver, or containing an unsupported promise of future work, plus a categorized reason drawn from a fixed implementation-side taxonomy (the taxonomy itself is not copied from upstream). On detection, the draft is appended to the run context, a repair instruction (fresh Konversio wording, marked as internal and not customer-visible) is issued, and the reply is regenerated once — tools remain available during repair. The repaired reply is re-verified; if it still cannot be verified safe, or if the guard errors after a detection already fired, the reply is suppressed and the conversation is handed off with a categorized reason identifying the guard. If the detector itself fails or returns an unusable result before any detection, the original reply is delivered (inconclusive is not a block).

Alternatives considered:

- Always-on guard. Rejected for v1: the extra detector call costs latency and tokens on every reply; opt-in lets operators adopt it where promise-abuse is observed.
- Regex/heuristic detection. Promise phrasing is too varied; an LLM detector with a two-outcome structured verdict is the upstream-proven shape.
- Block-on-detector-error. A detector outage would silence the assistant entirely; inconclusive results must not block delivery.

Rationale: the guard must be failure-isolated in both directions — never deliver a detected false promise, never block replies because the guard is down.

### Turn budget: conservative default, safe config, exhaustion = run failure

Keep `PILOT_AUTOPILOT_MAX_TURNS` as the configuration surface with a conservative default (Konversio's current 6; in any case the default MUST NOT exceed upstream's revised budget of 10). Non-positive or unparsable configuration falls back to the default. Turn-budget exhaustion must surface as a run failure and route through the existing error path (`handoff_on_error` in `Pilot::AutopilotInferenceJob`) rather than delivering whatever partial output exists.

- needs investigation: how the ai-agents runner signals turn-budget exhaustion in Konversio's pipeline (`run_result.failed?` vs a distinct error class), so the exhaustion path is wired to the error handoff explicitly rather than by accident.
- needs investigation: which configured model the detector should use in Konversio — upstream pins a specific detector model; Konversio resolves models via `Llm::Config`/`model_for`, and the guard should follow that resolution instead of hard-coding a provider model.
- needs investigation: where sentinel tokens (handoff/resolution) live once replies are structured parts — joined plain text is the likely parsing target, but the interaction must be settled during implementation so sentinels are never leaked into delivered part text.

## Risks / Trade-offs

- **Clean-room drift** -> The spec fixes behavior and data shape, not expression; reviewers compare implementation against this spec, never against upstream code. Prompt additions (budget disclosure, consent protocol, repair instruction) must be written fresh.
- **Prompt-growth risk** -> Budget disclosure and the consent protocol lengthen the system prompt; keep each section tight and measure generation behavior before/after.
- **Rewrite changing meaning** -> The shortening pass must be deterministic (temperature 0) and constrained to text fields; preservation invariants (part count, order, citations) are validated programmatically and any violation fails the response.
- **False positives in the promise guard** -> Legitimate statements ("here is what happens next") can look like promises; the two-outcome verdict with a reason category plus repair-before-block keeps the blast radius to a handoff, and the guard is opt-in.
- **Detector latency** -> One extra deterministic LLM call per guarded reply, plus a second on repair; acceptable for an opt-in integrity feature.
- **Sentinel leakage** -> With structured parts, sentinel parsing must run on the assembled plain text and sentinels must be stripped before delivery; covered in tasks and flagged as needs-investigation.

## Migration Plan

1. Land the budget-resolution service and prompt disclosure first (additive, no behavior change for replies already within budget).
2. Wire structured replies per assistant via citation config (per the sibling change), then the rewrite-or-fail enforcement.
3. Add the consent protocol to the assistant instruction assembly (wording-only change, all accounts).
4. Ship the promise guard behind the new account setting, default off; enable per account after observation.
5. Rollback: disable the account setting for the guard; remove the enforcement call to return to pre-enforcement delivery; prompt sections are inert once removed.

## Open Questions

- Should the promise guard also run before the rewrite pass, after it, or both? Current spec: guard runs on the final reply text that would be delivered (i.e., after any rewrite), since the rewrite must not introduce promises — but implementation may find guarding the pre-rewrite draft cheaper.
- Should guard-triggered handoffs surface a distinct operator-facing note in the conversation so humans know why the AI bailed? A private note with the categorized reason is proposed in tasks but the copy is a product decision.
