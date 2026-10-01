## Capability: pilot-session-detail-api

A per-message session detail endpoint and a dashboard inspection surface that show agents the model, turn context, cited sources, used FAQs, and participating scenarios behind a given AI-authored message.

---

## ADDED Requirements

### Requirement: session detail endpoint

The system SHALL expose an account-scoped endpoint under the `pilot` API namespace that returns the AI run session whose result is a given message. The endpoint is addressed by the message ID, MUST authorize the viewer via the existing conversation visibility policy, and MUST return 404 when the message has no recorded session.

#### Scenario: happy path payload

- Given an AI-authored message with a recorded session
- When an authorized agent requests the session detail for that message
- Then the response contains the session id, the message id, the model identifier, the usage figure (when recorded), and the run context as an array

#### Scenario: citations in the payload

- Given a session with cited documents
- When the detail is requested
- Then each citation entry contains the document id and title
- And a link only when the document's resolvable URL is `http(s)`; otherwise the link is null so the UI renders it as plain text

#### Scenario: used FAQs restricted to approved user-authored entries

- Given a session whose used FAQ ids include pending and user-authored approved entries
- When the detail is requested
- Then only approved, user-authored entries appear, each with id and question as its title

#### Scenario: participating scenarios resolved to titles

- Given a session with participating scenario ids
- When the detail is requested
- Then each scenario entry contains the scenario id and its title within the account

#### Scenario: missing session returns 404

- Given a message with no recorded session (predates the feature, non-AI message, or failed run)
- When the detail is requested
- Then the response is 404

#### Scenario: unauthorized viewer is rejected

- Given an agent without permission to view the message's conversation
- When the detail is requested
- Then the request is denied by the conversation policy

#### Scenario: cross-account access is impossible

- Given a message belonging to another account
- When the detail is requested with that message's id
- Then the response is 404

---

### Requirement: dashboard inspection surface on AI-authored messages

The dashboard SHALL offer an inspection affordance on AI-authored (Pilot-sent) messages that presents the session detail: the knowledge sources behind the reply and a humanized timeline of what the AI did during the run.

#### Scenario: knowledge sources shown

- Given a message whose session has cited documents and used FAQs
- When the agent opens the inspection surface
- Then cited documents appear with their links and used FAQs appear as sources of the reply

#### Scenario: run steps timeline

- Given a session with turn context
- When the agent opens the inspection surface
- Then a steps timeline shows tool calls with their arguments and scenario hops in order
- And message bodies and raw tool outputs are not echoed

#### Scenario: empty state for messages without sessions

- Given an AI-authored message with no recorded session
- When the agent opens the inspection surface
- Then a graceful empty state is shown instead of an error

---

### Requirement: session detail fetch caching

The dashboard SHALL cache session detail per message id to avoid refetching, while tolerating the race between message broadcast and session capture.

#### Scenario: recent 404 is retried later

- Given a message created moments ago whose session is not yet written
- When the detail request returns 404
- Then the miss is not cached permanently and a later interaction retries the fetch

#### Scenario: old 404 is cached as empty

- Given an older message whose detail request returns 404
- When the response arrives
- Then the miss is cached so the UI shows the empty state without refetching

#### Scenario: transient failures are never cached

- Given a detail request that fails with a server or network error
- When the failure occurs
- Then nothing is cached and a later interaction retries
