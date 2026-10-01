## Why

Konversio's fork base (Chatwoot v4.13.0) shipped the companies data model in core (the `companies` table, `contacts.company_id`, a `contacts_count` counter cache) and a list-only Companies page in the dashboard, but the entire backend for it — model, controllers, serializers, policy, association services — lived in the `enterprise/` overlay that the fork removed. Today `config/routes.rb` still mounts `resources :companies` pointing at a controller that does not exist, and the Companies UI is dead weight.

Between v4.14.0 and v4.18.0 upstream turned Companies into a real management surface (creation dialog, detail page, contact membership, notes, conversation history, custom attributes, activity tracking) and extended the contact workspace around it: conversation filtering by contact, contact filtering by company name, a media view on the contact details page, a company selector on contact forms, and preserving call records when contacts are merged. Konversio needs all of this rebuilt on MIT-clean ground.

## What Changes

- **Rebuild the Companies backend in the core tree** (clean-room, requirements-level — upstream implementation is EE-licensed and may not be copied): `Company` model with validations and activity rollup, account-scoped CRUD + search API with sorting and pagination, nested endpoints for company contacts / notes / conversations, custom-attribute management, avatar handling, and background deletion that cleanly detaches contacts.
- **Contact ↔ company association** (clean-room): denormalized `company_name` on contacts, automatic association of new contacts to companies via business email domains, company activity rollup from contact activity, and company-name sync to member contacts on rename.
- **Port the upstream core frontend verbatim-style** (MIT — porting is legal; referenced directly): company detail page with Contacts / Notes / History tabs, create dialog, delete confirmation, sort menu (including last activity and contacts count), company selector on contact forms, and the contact media sidebar.
- **Contact/company filtering** (MIT, core filter plumbing): filter conversations by `contact_id`, filter contacts by `company_name` as a standard attribute, and a data migration renaming the legacy `company` condition key in automation rules and saved contact filters.
- **Contact merge integrity** (requirements-level — upstream hook is EE-located): merging a contact reassigns its call records to the surviving contact, in the core `ContactMergeAction` (Konversio has no enterprise overlay to hook into).

## Capabilities

### New Capabilities
- `company-management`: Backend for companies — model, CRUD/search API, contact membership, aggregated notes and conversation history, custom attributes, avatar, activity tracking, association from email domain, and safe deletion.
- `companies-dashboard`: Companies UI — detail view with contacts/notes/history tabs, create and delete dialogs, sorting, and the company selector on contact forms.
- `contact-company-filters`: Filter conversations by contact, filter contacts by company name (standard attribute), media view on contact details, and the `company` → `company_name` filter-key migration.
- `contact-merge-integrity`: Contact merge preserves call records by reassigning them to the surviving contact.

### Modified Capabilities
None.

## Impact

- **New core backend files**: `app/models/company.rb`, `app/controllers/api/v1/accounts/companies_controller.rb`, `app/controllers/api/v1/accounts/companies/{base,contacts,conversations,notes}_controller.rb`, `app/policies/company_policy.rb`, `app/services/companies/{contact_membership_service,business_email_detector_service}.rb`, `app/services/contacts/company_association_service.rb`, `app/jobs/companies/{delete_job,sync_contact_names_job}.rb`, jbuilder views under `app/views/api/v1/accounts/companies/` and `app/views/api/v1/models/_company.json.jbuilder`.
- **Contact model**: `belongs_to :company` association (counter cache), company-name sync and activity callbacks.
- **Migrations**: port of upstream core migrations for `additional_attributes` / `custom_attributes` / `last_activity_at` on companies, and the `company` → `company_name` condition-key rename for automation rules and saved contact filters (fresh timestamps).
- **Routes**: extend the existing `resources :companies` block with member `avatar` / `destroy_custom_attributes` and nested `contacts` / `notes` / `conversations` endpoints.
- **Filter plumbing**: `lib/filters/filter_keys.yml` (`contact_id` for conversations, `company_name` for contacts), contact filter UI definitions.
- **Frontend**: port of upstream core `components-next/Companies/*`, companies routes/pages/store/api client, `ContactMedia.vue` and contact details layout wiring, `CompanySelector.vue` in contact forms, `en/companies.json` + contact i18n additions (en only).
- **Contact merge**: `app/actions/contact_merge_action.rb` gains call-record reassignment (active once a calls capability lands; see design).
