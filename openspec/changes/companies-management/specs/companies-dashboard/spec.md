## Capability: companies-dashboard

Dashboard UI for companies: a detail view with profile, member contacts, notes, and conversation history tabs; a create dialog; delete confirmation; extended sorting; and a company selector on contact forms. Ported from the upstream MIT core frontend with Konversio branding.

---

## ADDED Requirements

### Requirement: Company detail view

The dashboard SHALL provide a company detail page at a dedicated route, reachable from the companies list, showing the company profile and a tabbed sidebar with History, Notes, and Contacts.

#### Scenario: navigation from list to detail

- Given the companies list page
- When the user selects a company
- Then the company detail page opens for that company
- And breadcrumb/back navigation returns to the companies list

#### Scenario: profile card

- Given the detail page
- Then the profile shows the company avatar, name, domain, description, contacts count, and activity information
- And the profile can be edited in place

#### Scenario: sidebar tabs

- Given the detail page
- Then three tabs are available: conversation history, notes, and contacts
- And the contacts tab label includes the member count
- And tab content loads lazily when the tab is first opened

---

### Requirement: Member contacts tab

The contacts tab SHALL list member contacts with pagination and SHALL allow searching for and attaching existing contacts and detaching members.

#### Scenario: attach flow shows linkage context

- Given the attach-contact dialog with a candidate selected
- Then the dialog summarizes the target company and the candidate contact
- And when the candidate already belongs to another company, that current company is shown so the user understands the linkage will move

#### Scenario: member rows link to contacts

- When the user selects a member contact row
- Then the contact's own detail view opens

#### Scenario: detach requires confirmation context

- When the user removes a member
- Then the membership is cleared and the member list and count update without a page reload

---

### Requirement: History and notes tabs

The history tab SHALL render recent conversations of member contacts as standard conversation cards (including inbox, contact, and conversation labels), and the notes tab SHALL list recent notes across member contacts with author and contact attribution.

#### Scenario: empty states

- Given a company with no member activity
- Then each tab shows a distinct empty-state message instead of a blank panel

---

### Requirement: Company creation and deletion dialogs

The companies list page SHALL offer a create dialog (name required; domain, description, and avatar optional) and the detail page SHALL offer a confirmed delete action.

#### Scenario: create from the list page

- When the user submits the create dialog with a name
- Then the company is created and appears in the list

#### Scenario: delete is confirmed

- When the user chooses delete on the detail page
- Then a confirmation dialog explains that member contacts are kept and only the linkage is removed
- And on confirm the company is deleted and the user returns to the list

---

### Requirement: Sorting on the list page

The companies list SHALL offer sorting by name, domain, creation date, last activity, and contacts count, each in ascending or descending order.

#### Scenario: sort selection persists through pagination

- Given a selected sort and direction
- When the user changes pages
- Then the same sort and direction apply to the new page

---

### Requirement: Company selector on contact forms

Contact create/edit forms and the contact details view SHALL offer a company selector: a search-as-you-type combobox of account companies that also allows creating a new company inline.

#### Scenario: select existing company

- Given the contact form
- When the user types a company name and picks a match
- Then the contact is linked to that company on save

#### Scenario: inline create

- Given the selector with a query matching no existing company
- Then an option to create a company with that name is offered
- And choosing it opens the create dialog and links the new company on save

#### Scenario: current company visible before options load

- Given a contact already linked to a company
- When the selector opens before the company list has loaded
- Then the linked company's name is shown as the current value
