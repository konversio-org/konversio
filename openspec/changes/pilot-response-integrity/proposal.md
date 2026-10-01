## Why

Pilot autopilot replies currently go out as a single unstructured text blob with no guardrails around them. Five integrity gaps follow:

1. **No structured replies.** The model returns one flat string; there is no way to attach per-section source citations or to validate the reply's shape before delivery.
2. **No channel-aware length control.** An AI reply that exceeds a channel's character budget (SMS, WhatsApp, Instagram, …) is either rejected by the provider or silently truncated, and the assistant's generation prompt never tells the model a budget exists.
3. **No consent-first handoff contract.** Nothing in the assistant's behavioral rules pins down when a human handoff may be offered or executed, and nothing forbids the assistant from claiming a transfer happened when it did not.
4. **No false-promise guard.** The model can tell a customer it will "check on this and get back to you", "monitor your order", or "escalate this for you" — commitments it cannot keep, because nothing runs after the reply is sent. These erode trust more than a plain wrong answer.
5. **Unbounded-ish agent turn budgets.** The agent loop's turn budget must be a deliberate, conservative cap with defined failure behavior, not an incidental default.

Upstream Chatwoot addressed all five in its Enterprise tier across the v4.16–v4.18 line (structured response schema with per-part citations, a channel-aware message length limit with a rewrite-or-fail path, a consent-first handoff protocol in the assistant's core behavioral rules, a false-promise detection harness, and a sharp reduction of the agent loop's max-turns budget). Konversio needs the same guarantees, re-expressed as functional requirements for the MIT core tree under the `Pilot::` namespace.

## What Changes

- Give Pilot AI replies an optional structured form: an ordered list of reply parts, each carrying its text and the numeric indexes of the knowledge sources it relies on. Plain-text replies degrade gracefully to a single citation-free part. Structured parts are persisted on the resulting message for later inspection. (Extends the structured-reply mechanism specced in `pilot-agent-sessions-and-citations`.)
- Add a channel-aware reply length budget: resolve a per-conversation character budget from the channel type (with conversation-type and provider-medium overrides), tell the model the budget at generation time, measure the fully rendered customer message after generation, and when it exceeds the budget run exactly one shortening pass that preserves part count, order, citations, and facts. If the reply still does not fit, fail the response and hand off to a human instead of delivering an oversized or truncated message.
- Encode a consent-first handoff protocol in the assistant's behavioral rules: human handoff is executed only after the customer explicitly asks for a human or accepts an offer (or a configured guideline/guardrail mandates transfer for a matched condition); offers are made only when the customer is blocked or the issue exceeds the assistant's capabilities; the assistant never claims a transfer occurred unless the handoff mechanism actually executed.
- Add an opt-in, account-level false-promise guard: after a draft reply is generated and before delivery, a deterministic detector classifies the draft as safe or as containing an unsupported promise of future work. On detection, the reply is regenerated once with a repair instruction and re-verified; if it still cannot be verified safe, the reply is suppressed and the conversation is handed off to a human with a categorized reason.
- Pin the agent loop's turn budget: a conservative configurable default (not exceeding upstream's revised budget), with turn-budget exhaustion treated as a run failure that routes to the human-handoff error path rather than delivering a partial answer.

## Capabilities

### New Capabilities

- `pilot-multi-part-responses`: Structured Pilot replies composed of ordered parts with per-part source-citation indexes, graceful degradation to plain text, and persistence of the parts on the delivered message.
- `pilot-channel-length-limits`: Per-conversation reply length budgets derived from the channel, budget disclosure to the model at generation time, and a rewrite-or-fail enforcement path for oversized replies.
- `pilot-handoff-consent`: Consent-first protocol governing when the assistant may offer and execute a human handoff, and the prohibition on claiming transfers that did not happen.
- `pilot-false-promise-detection`: Opt-in post-generation guard that detects unsupported promises of future work in draft AI replies, repairs them once, and fails safe to a human handoff.
- `pilot-agent-turn-budget`: Bounded agent-loop turn budget with a conservative default, safe configuration handling, and defined failure behavior on exhaustion.

### Modified Capabilities

None.

## Impact

- Autopilot inference pipeline: `Custom::Pilot::AutopilotService` (`custom/app/services/custom/pilot/autopilot_service.rb`) — structured output contract, prompt additions (budget disclosure, consent protocol), rewrite pass, turn budget handling.
- Reply delivery pipeline: `Pilot::AutopilotInferenceJob` (`app/jobs/pilot/autopilot_inference_job.rb`) — post-generation guard invocation, fail-safe handoff routing.
- Handoff execution: `Custom::Pilot::HandoffService` and `Custom::Pilot::HandoverEvaluator` (`custom/app/services/custom/pilot/`) — consent-state awareness, categorized guard-triggered handoffs.
- `Pilot::Assistant` (`app/models/pilot/assistant.rb`) — citation gating reused; no schema change expected.
- `Account` settings (`app/models/account.rb`, `app/models/concerns/account_settings_schema.rb`) — new boolean setting for the false-promise guard.
- New Pilot domain services under `lib/pilot/` (length budget resolution, reply shortening, promise guard); no `enterprise/` paths, no new DB tables (no `pilot_` tables required — state rides on account settings and message `additional_attributes`).
- Outgoing AI messages: structured parts and guard metadata in `additional_attributes`.
- Channel models (`app/models/channel/`) — read-only use for budget resolution.
- English i18n only for any new operator-facing copy.
