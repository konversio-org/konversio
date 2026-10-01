## Capability: pilot-handoff-consent

The consent-first protocol governing when a Pilot assistant may offer and execute a human handoff, encoded in the assistant's behavioral rules. The protocol is a functional requirement on instruction assembly and handoff decision-making; all prompt wording is written fresh for Konversio.

---

## ADDED Requirements

### Requirement: consent-gated handoff execution

The assistant SHALL execute a human handoff only when at least one of these holds: the customer explicitly asks for human assistance; the customer accepts an offer to speak with a human; or a configured response guideline or guardrail mandates a transfer for a matched condition. A guideline- or guardrail-mandated transfer SHALL take precedence over the consent-first defaults.

#### Scenario: explicit customer request triggers handoff

- Given a customer message asking to speak to a human
- When the assistant responds
- Then the assistant executes the handoff mechanism

#### Scenario: accepted offer triggers handoff

- Given the assistant offered to connect the customer with a human and the customer accepted
- When the assistant responds next
- Then the assistant executes the handoff mechanism

#### Scenario: mandated transfer overrides consent defaults

- Given a configured guardrail that mandates transfer for a condition the conversation matches
- When the assistant responds
- Then the assistant executes the handoff without requiring an explicit customer request

#### Scenario: no handoff without consent or mandate

- Given a conversation where the customer neither requested nor accepted human assistance and no guideline or guardrail mandates transfer
- When the assistant responds
- Then the assistant does not execute a handoff, even if it cannot fully resolve the request

---

### Requirement: constrained handoff offers

The assistant SHALL offer to connect the customer with a human only when the customer appears blocked, repeats a request, rejects the clarification path, or the issue requires capabilities or permissions the assistant does not have, or repeated attempts to help have failed. The assistant SHALL NOT make such an offer as a first response to a merely unanswered question.

#### Scenario: single missed lookup does not trigger an offer

- Given a genuine in-scope question the documentation search did not answer on the first attempt
- When the assistant responds
- Then the assistant asks one focused clarifying question instead of offering a human

#### Scenario: blocked customer receives an offer

- Given the customer repeated the request after clarification failed
- When the assistant responds
- Then the assistant may offer to connect the customer with a human

---

### Requirement: no unexecuted transfer claims

The assistant MUST NOT tell the customer they have been transferred, escalated, or connected to a human unless the handoff mechanism actually executed during that turn. A handoff claim without an executed handoff is a protocol violation.

#### Scenario: transfer language accompanies only a real handoff

- Given a turn in which the handoff mechanism was not executed
- When the assistant's reply is examined
- Then the reply does not state or imply that a transfer has happened

#### Scenario: executed handoff may be acknowledged

- Given a turn in which the handoff mechanism executed
- When the assistant's reply is examined
- Then the reply may tell the customer a teammate will follow up

---

### Requirement: no re-offers while a handoff is pending

When a handoff has already been requested for the conversation and a human follow-up is pending, the assistant SHALL NOT offer a human again or re-emit a handoff signal; it SHALL keep helping from available knowledge and, when it cannot answer, briefly state that a teammate will follow up.

#### Scenario: pending handoff suppresses re-offers

- Given a conversation whose handoff state is pending
- When the assistant responds to a further customer message
- Then the reply contains no new handoff offer and no handoff signal

---

### Requirement: no promises of future work

The assistant MUST NOT commit to work that would happen after the current reply — checking back later, monitoring, following up, notifying, emailing, calling, refunding, cancelling, booking, escalating, or transferring — unless it completes that action within the current turn using an available tool. When the assistant cannot resolve the request now, it SHALL answer from what is verifiable now, ask one concrete clarifying question, or offer a human handoff without claiming one already happened.

#### Scenario: actionable commitment is completed in-turn

- Given a customer request the assistant can fulfill with an available tool
- When the assistant responds
- Then the assistant performs the action in this turn before describing it as done

#### Scenario: unactionable commitment is never made

- Given a customer request that would require work after the reply (e.g. monitoring an order)
- When the assistant responds
- Then the reply contains no commitment to perform that work later
