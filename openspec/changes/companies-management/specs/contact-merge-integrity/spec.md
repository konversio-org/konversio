## Capability: contact-merge-integrity

Merging a contact into another must not silently drop the mergee's call history. Call records follow the surviving contact, inside the same transactional merge that already moves conversations, messages, contact inboxes, and notes.

---

## ADDED Requirements

### Requirement: Merge reassigns call records

When two contacts are merged, the merge action SHALL reassign all call records of the mergee contact to the surviving (base) contact, within the same database transaction as the other merge steps, so a failure rolls back the entire merge.

#### Scenario: call history survives merge

- Given a mergee contact with call records and a base contact
- When the contacts are merged
- Then every call record formerly on the mergee belongs to the base contact
- And the mergee contact is removed as before

#### Scenario: no call records

- Given a mergee contact with no call records
- When the contacts are merged
- Then the merge succeeds unchanged

#### Scenario: transactional integrity

- Given a failure during any merge step
- Then call-record reassignment is rolled back together with conversation, message, contact-inbox, and note reassignment
- And both contacts remain as they were

---

### Requirement: Implementation lives in the core merge action

Because Konversio has no enterprise overlay, the call reassignment SHALL be implemented directly in the core contact merge action rather than through an overlay hook.

#### Scenario: no overlay dependency

- Given the merge codebase
- Then no `prepend_mod_with` or enterprise-namespace hook is involved in the call reassignment

> needs investigation: Konversio does not yet have a call record model (voice calling arrived upstream after the fork base and is covered by a separate parity change). This requirement becomes enforceable once the calls capability lands; the merge step must be added with it (or guarded so the merge action never references a missing model) and verified with the merge spec at that time.
