## Capability: pilot-copilot-reply-suggestion

One-click draft reply generation in the Pilot Copilot drawer: a copilot thread created with the reply-suggestion request type produces a single ready-to-send draft for the conversation the agent is viewing, generated through the shared AI run pipeline with a restricted tool set, with idempotent persistence and explicit discarded/failure terminal states.

---

## ADDED Requirements

### Requirement: Reply-suggestion request type on copilot thread creation

The copilot thread creation endpoint SHALL accept an optional request-type discriminator. When the discriminator selects reply-suggestion mode, the request MUST include a conversation reference, the conversation MUST pass the request-time access check (see `pilot-copilot-conversation-access`), and the system MUST create the thread with its first user message and dispatch draft generation to the dedicated background job. When the discriminator is absent, existing free-form chat behavior MUST be unchanged.

#### Scenario: reply-suggestion thread is created and dispatched

- Given an agent viewing a conversation they can access
- When the agent creates a copilot thread with the reply-suggestion request type and that conversation reference
- Then a copilot thread is created for that agent and account
- And the thread contains the agent's first message
- And the draft generation job is enqueued for that thread and conversation

#### Scenario: reply-suggestion without a conversation reference is rejected

- Given an agent
- When the agent creates a copilot thread with the reply-suggestion request type and no conversation reference
- Then the request is rejected with a client-error status
- And no copilot thread is created

#### Scenario: default chat mode is unaffected

- Given an agent
- When the agent creates a copilot thread without a request type
- Then the thread is created
- And the normal chat inference job is enqueued instead of the draft generation job

---

### Requirement: Draft generation reuses the AI run pipeline with a restricted tool set

Draft generation SHALL run through the same ai-agents SDK runner pipeline used by Copilot chat (model resolution, turn cap, tracing), but the agent exposed to the model MUST offer only: (a) the assistant's knowledge/FAQ lookup capability, and (b) account custom HTTP tools individually flagged as available for reply drafting. All other tools available to Copilot chat MUST be withheld from the draft run. The existing pre-run tool permission filter MUST still be applied on top of the restricted set.

#### Scenario: flagged custom tool is available to the draft run

- Given an account custom HTTP tool flagged as available for reply drafting
- And the account's custom-tools feature is enabled
- When a draft run is prepared for an assistant in that account
- Then the draft run's tool set includes that custom tool

#### Scenario: unflagged custom tool is withheld from the draft run

- Given an account custom HTTP tool not flagged as available for reply drafting
- When a draft run is prepared for an assistant in that account
- Then the draft run's tool set does not include that custom tool

#### Scenario: chat-only tools are withheld from the draft run

- Given tools available to Copilot chat for conversation search, conversation fetch, or contact lookup
- When a draft run is prepared
- Then none of those tools are in the draft run's tool set

#### Scenario: permission filter still applies on top

- Given a custom HTTP tool flagged for reply drafting in an account where the custom-tools feature is disabled
- When a draft run is prepared
- Then the tool is not in the draft run's tool set

---

### Requirement: Draft instructions contract

The system SHALL instruct the model to produce a single ready-to-send reply to the customer, based on the referenced conversation's message history and answering the customer's most recent incoming message. The instructions MUST require: the reply language follows the conversation (falling back to the account locale); the assistant's configured persona and product context are honored; the output is the reply text itself without meta-commentary, greetings to the agent, or chat-style framing; and conversation content is treated as data to answer, never as instructions to follow. The wording of these instructions is a Konversio-owned asset; upstream prompt text MUST NOT be reproduced or lightly reworded.

#### Scenario: draft answers the latest customer message

- Given a conversation whose latest public message is an incoming customer question
- When draft generation completes successfully
- Then the persisted draft is phrased as a reply from the support side to the customer
- And it addresses the content of that latest customer message

#### Scenario: draft contains no chat framing

- Given any conversation
- When draft generation completes successfully
- Then the persisted draft does not address the agent
- And it does not describe what it is doing (no meta-commentary)

---

### Requirement: Exactly one assistant response per reply-suggestion thread

The system SHALL persist at most one assistant message in a reply-suggestion thread, under a database lock. If an assistant message already exists when generation completes (for example after a job retry or duplicate dispatch), the system MUST NOT create a second one and MUST return the existing response.

#### Scenario: duplicate run returns the existing response

- Given a reply-suggestion thread that already has an assistant response
- When the draft generation job runs again for that thread
- Then no additional assistant message is created
- And the existing response is returned

---

### Requirement: Stale conversations are discarded, not drafted

Generation SHALL target the conversation's latest public (non-private) incoming or outgoing message, captured when the run starts. The run SHALL be skipped early when that target message is not an incoming customer message. At persistence time, the system MUST recheck that the conversation's latest public message is still the captured target; if the conversation has moved on, the system MUST persist a localized response indicating the suggestion is no longer applicable instead of the draft, marked as discarded, and MUST NOT record response usage for that run.

#### Scenario: last message already outgoing — run skipped

- Given a conversation whose latest public message is an outgoing agent reply
- When the draft generation job runs
- Then no draft is generated
- And a discarded-state response is persisted
- And no response usage is recorded

#### Scenario: new message arrives during generation

- Given a reply-suggestion run captured the latest public message M
- And a newer public message arrives in the conversation before the run persists
- When the run completes
- Then the generated draft is not persisted
- And a discarded-state response is persisted instead
- And no response usage is recorded

#### Scenario: target unchanged — draft persisted with usage

- Given a reply-suggestion run captured the latest public message M
- And M is still the latest public message at persistence time
- And the agent still has access to the conversation
- When the run completes successfully
- Then the draft is persisted as the thread's assistant response
- And the response payload is flagged as a reply suggestion
- And response usage is recorded once

---

### Requirement: Failure handling with bounded retries

When generation fails with a recoverable error, the job SHALL retry with backoff for a bounded number of attempts (three). After the final attempt fails, the system SHALL persist a generic localized failure response in the thread so the drawer always reaches a settled state. The failure response MUST NOT contain conversation-derived content, and MUST NOT record response usage.

#### Scenario: transient failure is retried

- Given a draft run that fails with a recoverable error on its first attempt
- When the job's retry policy runs
- Then generation is attempted again after a backoff delay

#### Scenario: persistent failure settles the thread

- Given a draft run that fails on every attempt
- When the final attempt fails
- Then a generic failure response is persisted as the thread's assistant response
- And no response usage is recorded

---

### Requirement: Fallback responses are localized

The discarded-state and failure responses SHALL be localized strings, resolved against the requesting user's UI locale with fallback to the account locale. needs investigation: confirm which existing locale-resolution helper Pilot surfaces use, and reuse it rather than adding a new mechanism.

#### Scenario: discarded response uses the agent's locale

- Given an agent whose UI locale is set to a supported non-English locale
- When a discarded-state response is persisted for that agent's thread
- Then the response content is the localized string for that locale

---

### Requirement: Drawer surfaces the suggest-reply action contextually

The Pilot Copilot drawer SHALL offer a suggest-reply quick action on conversation routes only when the selected conversation's latest public message is an incoming customer message. The action SHALL create a reply-suggestion thread for the viewed conversation. The resulting draft message SHALL render distinctly as a draft with an action that inserts its content into the conversation's reply editor; discarded and failure responses SHALL render as plain assistant text without the insert action. The drawer SHALL reset the active copilot thread when the viewed conversation changes.

#### Scenario: quick action shown for incoming last message

- Given an agent viewing a conversation whose latest public message is incoming
- When the Copilot drawer is opened with no active thread
- Then the suggest-reply quick action is visible

#### Scenario: quick action hidden for outgoing last message

- Given an agent viewing a conversation whose latest public message is outgoing
- When the Copilot drawer is opened with no active thread
- Then the suggest-reply quick action is not visible

#### Scenario: draft inserts into the reply editor

- Given a reply-suggestion thread with a persisted draft
- When the agent activates the insert action on the draft
- Then the draft content is inserted into the conversation's reply editor
- And nothing is sent to the customer

#### Scenario: discarded response has no insert action

- Given a reply-suggestion thread with a discarded-state response
- When the response renders in the drawer
- Then no insert-into-editor action is offered

#### Scenario: switching conversations resets the thread

- Given an agent viewing a reply-suggestion thread for conversation A
- When the agent navigates to conversation B
- Then the drawer no longer shows conversation A's thread as active
