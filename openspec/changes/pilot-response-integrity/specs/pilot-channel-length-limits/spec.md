## Capability: pilot-channel-length-limits

Per-conversation reply length budgets derived from the destination channel, disclosed to the model at generation time, and enforced after generation with a rewrite-or-fail path: an AI reply that cannot be made to fit the budget is never delivered — the conversation is handed off to a human instead.

---

## ADDED Requirements

### Requirement: per-conversation budget resolution

The system SHALL resolve a character budget for each conversation using this precedence: (1) Instagram direct-message conversations are capped at 1,000 characters regardless of inbox channel; (2) Twilio inboxes are capped by the channel's medium — 320 for SMS, 1,600 for WhatsApp; (3) the inbox's channel type — Facebook 2,000, Instagram 1,000, LINE 5,000, SMS 320, Telegram 4,096, TikTok 6,000, WhatsApp 4,096; (4) any other channel type — 10,000. Budget resolution with no conversation SHALL yield no budget.

#### Scenario: channel type determines the budget

- Given a conversation on a WhatsApp inbox
- When the budget is resolved
- Then the budget is 4,096 characters

#### Scenario: Twilio medium overrides the channel table

- Given a conversation on a Twilio inbox whose medium is WhatsApp
- When the budget is resolved
- Then the budget is 1,600 characters

#### Scenario: Instagram direct-message override

- Given a conversation marked as an Instagram direct message, on an inbox whose channel type would otherwise allow more
- When the budget is resolved
- Then the budget is 1,000 characters

#### Scenario: default for unconstrained channels

- Given a conversation on a web widget inbox
- When the budget is resolved
- Then the budget is 10,000 characters

#### Scenario: no conversation means no budget

- Given a generation run with no conversation (e.g. playground)
- When the budget is resolved
- Then no budget applies and no length enforcement occurs

---

### Requirement: budget disclosure at generation time

When a budget applies, the assistant's generation instructions SHALL tell the model the reply must stay within the budget so it can be delivered on this channel. When no budget applies, no length instruction SHALL be added.

#### Scenario: budget is disclosed

- Given a conversation on an SMS inbox (budget 320)
- When the assistant instructions are assembled
- Then the model is told the reply must fit within 320 characters

#### Scenario: no disclosure without a budget

- Given a generation run with no conversation
- When the assistant instructions are assembled
- Then no character-budget instruction is present

---

### Requirement: rewrite-or-fail enforcement

After generation, the system SHALL measure the fully rendered customer message — part texts plus citation link markup — against the budget. If the message fits, it SHALL be delivered untouched. If it exceeds the budget, the system SHALL attempt exactly one shortening pass whose result must preserve part count, part order, citation assignment, factual content, and valid markdown; the result SHALL be re-measured. A reply that still exceeds the budget after the shortening pass MUST NOT be delivered and SHALL fail the response, routing to the human-handoff error path. If citation link markup alone exceeds the budget, the response SHALL fail without attempting a shortening pass.

#### Scenario: within-budget reply is delivered untouched

- Given a rendered reply of 800 characters on a WhatsApp inbox
- When enforcement runs
- Then no shortening pass is attempted and the reply is delivered as generated

#### Scenario: oversized reply is shortened once and delivered

- Given a rendered reply of 5,000 characters on a WhatsApp inbox
- When enforcement runs
- Then exactly one shortening pass runs
- And the shortened reply fits within 4,096 characters and is delivered
- And the part count, part order, and citation assignment are unchanged

#### Scenario: citation-markup-only overflow fails without rewrite

- Given a reply whose citation link markup alone exceeds the budget
- When enforcement runs
- Then no shortening pass is attempted and the response fails to the handoff path

#### Scenario: still-oversized reply after rewrite is not delivered

- Given an oversized reply whose shortened form still exceeds the budget
- When enforcement completes
- Then no AI reply is delivered
- And the conversation is handed off to a human via the error path

#### Scenario: rewrite violating preservation invariants fails the response

- Given a shortening pass that changed the number of parts or the citation order
- When enforcement validates the result
- Then the response fails to the handoff path instead of delivering the altered reply

---

### Requirement: shortening pass constraints

The shortening pass SHALL run as a single-turn agent run at temperature 0, instructed (in freshly written Konversio wording) to shorten only the text of each part while preserving names, numbers, dates, links, warnings, completed actions, and markdown validity, and forbidden from adding facts. When citations are enabled, the system SHALL re-attach the original per-part citation indexes to the shortened output regardless of what the shortening run returned.

#### Scenario: shortening run is deterministic and single-turn

- Given an oversized reply
- When the shortening pass runs
- Then it executes with a single-turn budget and temperature 0

#### Scenario: original citations are re-attached

- Given an oversized reply with citations enabled
- When the shortening pass returns text with altered or missing indexes
- Then the delivered shortened parts carry the original per-part citation indexes
