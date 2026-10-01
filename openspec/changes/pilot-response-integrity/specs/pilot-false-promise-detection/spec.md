## Capability: pilot-false-promise-detection

An opt-in, account-level guard that inspects each draft autopilot reply before delivery, detects unsupported promises of future work, repairs the reply once, and fails safe to a human handoff when the reply cannot be verified safe. The guard is failure-isolated in both directions: a detected false promise is never delivered, and a guard malfunction never blocks delivery on its own.

---

## ADDED Requirements

### Requirement: account-level opt-in

The guard SHALL run only when a dedicated boolean account setting is enabled. When the setting is absent or disabled, no detection call SHALL be made and delivery is unchanged.

#### Scenario: setting disabled — no detection

- Given an account with the guard setting disabled
- When an autopilot reply is generated
- Then the reply is delivered without any detector call

#### Scenario: setting enabled — detection runs

- Given an account with the guard setting enabled
- When an autopilot reply is generated
- Then the draft reply is inspected before delivery

---

### Requirement: detection contract

The detector SHALL be a separate, deterministic (temperature 0) model call with a structured verdict: given the conversation context and the draft reply, it SHALL return exactly one of two outcomes — the reply is safe to deliver, or it contains an unsupported promise of future work — plus a categorized reason drawn from a fixed implementation-side taxonomy, and the model used. An unsupported promise of future work is any commitment to act after the reply is sent (later checking or investigation, monitoring, follow-up, notification, email, callback, or background escalation) that the assistant did not complete within the turn. A detector failure or unusable detector output SHALL yield an inconclusive result, never an exception into the delivery path.

#### Scenario: safe reply verdict

- Given a draft reply that answers from verifiable information with no future commitments
- When the detector runs
- Then the verdict is safe to deliver and the reply proceeds to delivery

#### Scenario: future-work promise verdict

- Given a draft reply telling the customer the assistant will check on the issue and follow up later
- When the detector runs
- Then the verdict is an unsupported future-work promise with a categorized reason

#### Scenario: detector failure is inconclusive

- Given the detector call errors or returns output that cannot be interpreted
- When the guard processes the result
- Then the result is treated as inconclusive and the original reply is delivered

---

### Requirement: repair-once and re-verify

On a future-work-promise verdict, the system SHALL regenerate the reply exactly once: the draft is appended to the run context together with an internal, not customer-visible repair instruction (written in fresh Konversio wording) directing the assistant to answer from what it can verify now, ask one concrete clarifying question, or offer a human handoff without claiming one happened — tools remaining available. The repaired reply SHALL be re-inspected by the detector. A repaired reply verified safe SHALL be delivered; a repaired reply that cannot be verified safe MUST NOT be delivered.

#### Scenario: repaired reply verified safe is delivered

- Given a draft flagged as a future-work promise
- When the repair regeneration produces a reply the detector verifies as safe
- Then the repaired reply is delivered instead of the draft

#### Scenario: repaired reply still flagged is suppressed

- Given a draft flagged as a future-work promise
- When the repaired reply is also flagged
- Then no AI reply is delivered
- And the conversation is handed off to a human with a categorized reason identifying the guard

---

### Requirement: fail-safe behavior

The guard SHALL fail safe to a human handoff whenever a false promise was detected and the guard cannot complete verification — including guard errors after a detection fired. The guard SHALL be skipped when the run already requested a handoff. Guard-triggered handoffs SHALL carry a categorized reason distinguishing them from customer-requested handoffs, and every detection (verdict, reason, model, account, conversation) SHALL be logged.

#### Scenario: guard error after detection forces handoff

- Given a draft flagged as a future-work promise
- When the repair or re-verification step errors
- Then no AI reply is delivered
- And the conversation is handed off with a categorized guard reason

#### Scenario: guard skipped when handoff already requested

- Given a run whose reply already signals a handoff
- When the guard would run
- Then no detection call is made for that reply

#### Scenario: detections are auditable

- Given any detector run
- When it completes
- Then a log entry records the verdict, categorized reason, model, account, and conversation

---

### Requirement: isolation from delivery

The guard SHALL run after generation and before delivery, and MUST NOT raise into the delivery path: any internal guard failure is contained (logged and tracked) and resolved as either delivery of the original reply (no prior detection) or a fail-safe handoff (a detection already fired).

#### Scenario: detector outage does not silence the assistant

- Given the guard is enabled and the detector is unreachable before any detection
- When an autopilot reply is generated
- Then the reply is delivered and the guard failure is logged

- needs investigation: whether the guard inspects the pre-rewrite draft, the final post-rewrite text, or both (see design.md open question); the wiring point in `Pilot::AutopilotInferenceJob` vs `Custom::Pilot::AutopilotService` must be settled during implementation.
