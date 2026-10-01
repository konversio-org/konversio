## Capability: pilot-faq-suggestion-review

Review API and interface for FAQ suggestions: list and search an assistant's open suggestions, inspect the conversations that produced them, edit question and answer, approve (converting the suggestion into an approved knowledge entry), and dismiss (suppressing future re-mining of the same FAQ).

---

## ADDED Requirements

### Requirement: suggestion listing endpoint

The system SHALL expose a paginated list of an account's FAQ suggestions under the Pilot account API namespace, supporting filters by assistant and status, a case-insensitive text search over question and answer, and a default page size of 25. The response MUST include a metadata block with the total matching count and current page.

#### Scenario: list open suggestions for an assistant

- Given an assistant with three open and two dismissed suggestions
- When an authorized user requests the suggestion list filtered to that assistant and status `open`
- Then exactly the three open suggestions are returned
- And the metadata reports a total count of three

#### Scenario: search matches question or answer

- Given open suggestions exist
- When the list is requested with a search term appearing in one suggestion's answer
- Then that suggestion is included in the results
- And suggestions whose question and answer both lack the term are excluded

#### Scenario: pagination

- Given more than 25 matching suggestions
- When page 2 is requested
- Then the next slice of up to 25 records is returned with the correct page metadata

---

### Requirement: permission-scoped visibility

Administrators SHALL see all suggestions in the account. Non-admin agents SHALL see only suggestions that have at least one observation on a conversation accessible to them under the existing conversation permission filter. The same filter applies to the source-conversation preview on the detail endpoint.

#### Scenario: administrator sees everything

- Given an administrator
- When the suggestion list is requested
- Then all of the account's suggestions matching the filters are returned

#### Scenario: agent sees only own-scope suggestions

- Given a non-admin agent with access limited to one inbox
- And a suggestion observed only in conversations of another inbox
- When the agent requests the suggestion list
- Then that suggestion is not returned
- And requesting its detail directly returns not-found

#### Scenario: source preview hides inaccessible conversations

- Given a suggestion with observations on two conversations, only one accessible to the requesting agent
- When the agent requests the suggestion detail
- Then only the accessible conversation appears in the source preview

---

### Requirement: suggestion detail with source conversations

The detail endpoint SHALL return the suggestion plus a preview of its most recent source conversations (up to 50), each exposing the conversation id and display id alongside the generated question, answer, language, and observation status for that sighting.

#### Scenario: reviewer inspects evidence

- Given an open suggestion with a source count of three
- When an authorized user requests its detail
- Then the response includes the suggestion fields and the permission-filtered observations
- And each observation identifies its conversation so the UI can deep-link to it

---

### Requirement: editing is restricted to open suggestions

Question and answer edits SHALL be accepted only while the suggestion is open, under a row lock; attempts to edit an approved or dismissed suggestion MUST behave as not-found. Blank question or answer values MUST be rejected.

#### Scenario: edit an open suggestion

- Given an open suggestion
- When an authorized user updates its question and answer
- Then the new values are persisted
- And the suggestion remains open

#### Scenario: edit after decision fails

- Given a dismissed suggestion
- When an update is attempted
- Then the request fails as if the record were not found
- And the stored values are unchanged

---

### Requirement: approval converts to an approved knowledge entry

Approval SHALL be an atomic, locked operation: it MUST refuse non-open suggestions, apply any final edits supplied with the request, create an approved `Pilot::AssistantResponse` from the resulting question and answer, and mark the suggestion approved. The response payload is the created knowledge entry. Approval with no edits uses the suggestion's current text.

#### Scenario: approve creates searchable knowledge

- Given an open suggestion with question Q and answer A
- When it is approved without edits
- Then an approved `Pilot::AssistantResponse` exists for the same assistant with question Q and answer A
- And the suggestion's status is `approved`
- And the knowledge entry participates in customer-facing FAQ retrieval

#### Scenario: approve with final edits

- Given an open suggestion
- When it is approved with a corrected answer
- Then the created knowledge entry carries the corrected answer
- And the suggestion records the corrected answer as its final state

#### Scenario: double approval is impossible

- Given a suggestion approved by one reviewer
- When a second approval request for the same suggestion is processed
- Then it fails as not-found
- And exactly one knowledge entry was created

---

### Requirement: dismissal is terminal and sticky

Dismissing SHALL be allowed only on open suggestions, under a row lock, and MUST mark the suggestion dismissed. Dismissed suggestions remain stored so the mining matcher can suppress future sightings of the same FAQ in the same language.

#### Scenario: dismiss removes from review queue

- Given an open suggestion
- When it is dismissed
- Then its status is `dismissed`
- And it no longer appears in default (open) list results

#### Scenario: dismissed suggestion suppresses re-mining

- Given a dismissed suggestion in language `en`
- When a later conversation yields a candidate judged the same FAQ in `en`
- Then no new suggestion is created
- And a discarded observation is recorded

---

### Requirement: review interface in the Pilot FAQs area

The Pilot FAQs page SHALL surface an entry point showing the count of open suggestions for the selected assistant, linking to a suggestions page. The suggestions page SHALL list open suggestions with search and pagination, and offer per-suggestion quick approve, quick dismiss, and a review dialog. The review dialog SHALL present editable question and answer fields (both required), the suggestion's source conversations with deep links, and save / approve / dismiss actions.

#### Scenario: open count is visible on the FAQs page

- Given an assistant with two open suggestions
- When the user opens that assistant's FAQs page
- Then an entry point indicates two suggestions awaiting review
- And activating it navigates to the suggestions page

#### Scenario: reviewer approves from the dialog

- Given the review dialog open on a suggestion
- When the reviewer edits the answer and chooses approve
- Then the suggestion is approved with the edited text
- And it disappears from the open list
- And the corresponding knowledge entry is visible in the FAQs list

#### Scenario: reviewer jumps to a source conversation

- Given the review dialog showing two source conversations
- When the reviewer activates one
- Then the application navigates to that conversation

#### Scenario: mutation feedback and list refresh

- Given the suggestions page
- When an approve or dismiss completes
- Then a success or error message is shown
- And the list refreshes, staying on a valid page when the last item of a page is removed
