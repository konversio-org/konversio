## Capability: pilot-copilot-conversation-access

Permission resolution that determines which conversations a given agent may reference from Pilot Copilot surfaces, enforced when a reply-suggestion request is accepted and again before any generated content is persisted.

---

## ADDED Requirements

### Requirement: Access resolution mirrors conversation-list visibility

The system SHALL resolve the set of conversations an agent may reference from Copilot surfaces to exactly the conversations that agent can see in the account's conversation list: administrators MAY reference any conversation in the account; non-admin agents MAY reference only conversations permitted to them by the platform's existing conversation permission model (role, inbox membership, and any team or custom-role scoping the platform applies). The resolution MUST reuse the existing conversation permission-filter plumbing rather than a parallel access-control implementation.

#### Scenario: administrator can reference any conversation

- Given an administrator of the account
- When access is resolved for any conversation in the account
- Then the conversation is accessible

#### Scenario: agent can reference a conversation visible to them

- Given a non-admin agent who can see a conversation in their conversation list
- When access is resolved for that conversation
- Then the conversation is accessible

#### Scenario: agent cannot reference a conversation outside their visibility

- Given a non-admin agent who cannot see a conversation in their conversation list
- When access is resolved for that conversation
- Then the conversation is not accessible

---

### Requirement: Request-time enforcement with non-leaking rejection

Copilot API endpoints that accept a conversation reference for reply-suggestion mode MUST resolve access synchronously before accepting the request, and MUST reject inaccessible references with a not-found (404) response. The response MUST NOT distinguish between "conversation does not exist" and "conversation exists but is not accessible to you", and MUST NOT use a forbidden (403) status for inaccessible conversations.

#### Scenario: inaccessible conversation reference is rejected as not-found

- Given an agent who cannot see conversation with display id 123
- When the agent creates a copilot thread with reply-suggestion request type referencing conversation 123
- Then the request is rejected with HTTP 404
- And no copilot thread is created

#### Scenario: rejection shape is identical for missing and inaccessible conversations

- Given an agent
- When the agent references a conversation that does not exist
- And the agent references a conversation that exists but is not accessible to them
- Then both responses have the same status code and the same error shape

---

### Requirement: Persistence-time re-verification

Before persisting a generated draft into a copilot thread, the system MUST re-verify that the requesting agent still has access to the referenced conversation. If access has been revoked since the request was accepted, the system MUST NOT persist the draft content, and MUST persist a generic localized failure response instead.

#### Scenario: access revoked during generation blocks the draft

- Given a reply-suggestion request was accepted for a conversation
- And the agent's access to that conversation is revoked while generation is running
- When generation completes
- Then the draft content is not persisted
- And a generic failure response is persisted in the thread
- And the failure response contains no conversation-derived content
