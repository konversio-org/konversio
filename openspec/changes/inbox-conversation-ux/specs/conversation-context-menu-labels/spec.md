## Capability: conversation-context-menu-labels

Searchable label assignment in the conversation right-click context menu.

---

## ADDED Requirements

### Requirement: Label search in the context menu

The Labels submenu of the conversation card context menu SHALL include a search input that fuzzy-filters account labels by title. Assigned labels MUST sort before unassigned ones (each group keeping its existing order), and an empty state MUST be shown when no label matches.

#### Scenario: filtering labels by search text

- Given a conversation whose account has labels `billing`, `billing-refund`, and `urgent`
- When the user opens the context menu Labels submenu and types `bill`
- Then only `billing` and `billing-refund` are listed

#### Scenario: assigned labels first

- Given label `urgent` is assigned to the conversation and `billing` is not
- When the user opens the Labels submenu
- Then `urgent` appears before `billing`, whether or not a search query is entered

#### Scenario: no matches

- Given the search query matches no account label
- Then a "no labels found" empty state is shown in place of the list

#### Scenario: searching does not close the menu

- Given the Labels submenu is open
- When the user clicks into the search input and types
- Then the context menu remains open and keystrokes are not interpreted as global shortcuts

---

### Requirement: Toggle assignment from search results

Clicking a label in the submenu MUST assign it when unassigned and remove it when assigned, visually distinguishing assigned labels.

#### Scenario: assign from the menu

- Given `billing` is unassigned
- When the user clicks `billing` in the Labels submenu
- Then the label is assigned to the conversation and a success toast names the label and conversation

#### Scenario: remove from the menu

- Given `urgent` is assigned
- When the user clicks `urgent` in the Labels submenu
- Then the label is removed and a success toast is shown

#### Scenario: context-menu label removal preserves bulk selection

- Given the user has an active bulk selection in the chat list
- When the user removes a label on a single conversation via the context menu
- Then the bulk selection is not cleared
