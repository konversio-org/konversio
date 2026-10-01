## Capability: conversation-bulk-actions

Bulk operations on selected conversations from the chat list: agent/team assignment, label add and remove, status and snooze updates.

---

## ADDED Requirements

### Requirement: Bulk action bar

When one or more conversations are selected in the chat list, a bulk action bar SHALL replace the list header and offer: assign agent, assign team, add labels, remove labels, and status updates (open, resolve, snooze including a custom-time option). A select-all checkbox MUST select or clear the currently loaded conversation list.

#### Scenario: selecting conversations reveals the bar

- Given the chat list is displayed
- When the user selects one or more conversations via their checkboxes
- Then the bulk action bar appears with a count of selected conversations

#### Scenario: select all

- Given the bulk action bar is visible
- When the user checks the select-all checkbox
- Then all currently loaded conversations in the list are selected
- When the user unchecks it
- Then the selection is cleared

---

### Requirement: Bulk label add and remove

The bulk action bar MUST support adding labels to and removing labels from all selected conversations through the bulk actions API (`labels: { add: [...] }` and `labels: { remove: [...] }`). The remove-labels menu SHOULD be scoped to labels actually applied to the current selection.

#### Scenario: bulk add labels

- Given three conversations are selected
- When the user picks label `billing` in the add-labels menu
- Then the bulk actions API is called with the selected IDs and `labels: { add: ["billing"] }`
- And the selection is cleared and a success toast is shown

#### Scenario: bulk remove labels

- Given three selected conversations that variously carry labels `billing` and `urgent`
- When the user opens the remove-labels menu
- Then only labels present on at least one selected conversation are offered
- When the user removes `billing`
- Then the bulk actions API is called with `labels: { remove: ["billing"] }`
- And the selection is cleared and a success toast is shown

#### Scenario: failure keeps feedback honest

- Given a bulk label operation fails
- Then a failure toast is shown

---

### Requirement: Bulk status updates with required-attribute guard

Bulk resolve MUST skip selected conversations that are missing inbox-required custom attributes, and MUST report partial or total skips.

#### Scenario: bulk resolve with all attributes satisfied

- Given selected conversations all satisfy their inboxes' required attributes
- When the user bulk-resolves
- Then the bulk actions API is called with `fields: { status: "resolved" }` for all selected IDs

#### Scenario: bulk resolve partially skipped

- Given two of five selected conversations are missing required attributes
- When the user bulk-resolves
- Then only the three valid IDs are submitted
- And a partial-success toast indicates some conversations were skipped

#### Scenario: bulk resolve fully blocked

- Given every selected conversation is missing required attributes
- When the user bulk-resolves
- Then no API call is made
- And a toast explains the conversations cannot be resolved

#### Scenario: bulk snooze with custom time

- Given conversations are selected
- When the user chooses snooze → custom time and picks a datetime
- Then the bulk actions API is called with `fields: { status: "snoozed" }` and the chosen `snoozed_until` epoch
