## Context

The fork base (Chatwoot v4.13.0) already carries the companies schema and a list-only Companies page in core, but every backend piece was in the removed `enterprise/` overlay — so Konversio today has live routes (`resources :companies`) and a live frontend pointed at a backend that does not exist. Upstream v4.14.0–v4.18.0 filled out the feature on both sides.

License split for this change (mixed axis):

- **Clean-room (EE upstream — reference for understanding only, requirements-level spec):**
  - `enterprise/app/controllers/api/v1/accounts/companies_controller.rb` and nested `companies/{base,contacts,conversations,notes}_controller.rb`
  - `enterprise/app/models/company.rb`, `enterprise/app/policies/company_policy.rb`, `enterprise/app/models/enterprise/concerns/contact.rb`
  - `enterprise/app/services/companies/{contact_membership_service,business_email_detector_service}.rb`, `enterprise/app/services/contacts/company_association_service.rb`
  - `enterprise/app/jobs/companies/{delete_job,sync_contact_names_job}.rb`, EE jbuilder views
  - `enterprise/app/actions/enterprise/contact_merge_action.rb` (the call-merge hook)
- **MIT port reference (core upstream — verbatim porting is legal):**
  - All frontend: `app/javascript/dashboard/components-next/Companies/*`, `routes/dashboard/companies/*`, `stores/companies.js`, `api/companies.js`, `i18n/locale/en/companies.json`, `components-next/Contacts/ContactsSidebar/ContactMedia.vue`, contact form/filter wiring
  - `lib/filters/filter_keys.yml` additions (`contact_id`, `company_name` rename)
  - Core migrations `20260422133000_add_additional_attributes_to_companies.rb` and `20260427094500_rename_company_condition_key_in_automation_rules.rb`

The upstream Companies API at v4.18.0 is RESTful under `/api/v1/accounts/:account_id/companies`, with nested `contacts`, `contacts/search`, `notes`, `conversations`, `avatar`, and `destroy_custom_attributes` endpoints. The MIT frontend we port calls exactly these paths, so the route shape is a hard functional contract; everything behind the routes is written fresh in Konversio style.

## Goals / Non-Goals

**Goals:**

- A working Companies backend in the core tree (`app/`, no `enterprise/`), exposing the route contract the ported frontend expects.
- Company detail surface: profile, member contacts (add/remove/search), aggregated notes from member contacts, recent conversation history, custom attributes, avatar.
- Activity tracking: `last_activity_at` on companies, roll-up from member contact activity with a write-throttle.
- Automatic contact→company association from business email domains; denormalized `company_name` on contacts kept in sync.
- Filtering: conversations by `contact_id`; contacts by `company_name` as a standard attribute; legacy `company` condition keys migrated.
- Contact merge reassigns call records to the surviving contact.
- Port the upstream v4.18.0 core Companies/contacts UI, rebranded (Konversio, not Chatwoot), en locale only.

**Non-Goals:**

- Cloud plan gating ("Business plan") — Konversio is self-hosted only; no plan checks.
- Voice/calling itself (the calls capability is a separate change; this change only fixes merge behavior for when it exists).
- Any Pilot:: functionality; companies are a CRM surface, not AI.
- Non-English locales.
- Upstream's enterprise overlay mechanics (`prepend_mod_with`, `EnterpriseAccountsController`) — Konversio has no overlay; everything is core.

## Decisions

### Clean-room the backend, port the frontend

The EE backend files were read to understand behavior (endpoints, validations, association rules, deletion semantics) but the spec expresses requirements in original wording; implementation must be written fresh against this spec. The core frontend is MIT and is ported directly from upstream v4.18.0 with rebranding — no clean-room needed there.

Alternatives considered:
- Clean-room the frontend too: unnecessary legal caution; the frontend is core MIT.
- Skip the backend and drop the Companies UI: leaves dead routes/UI and forfeits parity.

Rationale: minimal legal risk with maximal parity.

### Enable companies unconditionally (no plan gating)

Upstream gates the API behind an account feature flag plus cloud-plan checks. Konversio is self-hosted, 100% MIT, with no plans. The companies capability is enabled for every account; no `ensure_companies_enabled!`-style gate is carried over.

Alternatives considered:
- Keep a `companies` feature flag defaulting on: adds config surface nobody on self-hosted needs; revisit only if operators ask for an opt-out.

### Where the code lands

Everything lands in core Konversio paths: `app/models/company.rb`, `app/controllers/api/v1/accounts/companies_controller.rb` + `app/controllers/api/v1/accounts/companies/*_controller.rb`, `app/policies/company_policy.rb`, `app/services/companies/*`, `app/services/contacts/company_association_service.rb`, `app/jobs/companies/*`. These paths are the Rails-conventional locations for the route contract — they are dictated by routing, not copied expression. Contact-side behavior (company association, name sync, activity callbacks) goes directly into `app/models/contact.rb` or a core concern — never via `prepend_mod_with`.

### Denormalized `company_name` on contacts

Contacts carry `company_name` inside `additional_attributes`, written whenever `company_id` changes, synced across member contacts (batched, callback-free) when a company is renamed, and stripped on company deletion. This powers contact list display, contact sorting/filtering by company, and automation conditions without a join.

Alternatives considered:
- Always join to companies at read time: breaks the existing `additional_attributes`-based filter/sort machinery the contact list already uses.

Rationale: the contact filter/sort pipeline already reads `additional_attributes`; denormalization is the compatible path. The sync-on-rename and strip-on-delete jobs keep it consistent.

### Activity rollup with throttle

Companies get `last_activity_at`. When a member contact's `last_activity_at` advances, the company's is advanced too — but writes are throttled (no company update if the stored value is within a short rollup window of the new timestamp) to avoid a write per message on hot ingest paths. Contact assignment to a company also seeds the rollup from the contact's current activity.

### Deletion as a background job with quiet cleanup

Company deletion enqueues a background job that first nullifies member contacts' `company_id` and strips their denormalized `company_name` in batches **without firing contact callbacks** (no automations, no webhook storms), then destroys the company. The API returns success immediately after enqueueing.

### Contact merge and call records

Upstream implements call preservation as an enterprise overlay hook on `ContactMergeAction`. Konversio has no overlay: the core `app/actions/contact_merge_action.rb` gains a merge step that reassigns `Call` records from the mergee to the base contact, alongside the existing conversation/message/note/contact-inbox steps, inside the same transaction.

**needs investigation:** Konversio has no `Call` model yet (voice calling arrived upstream after the fork base and is tracked as a separate parity change). The merge step MUST be added in the same change that introduces the calls table/model, or guarded so `ContactMergeAction` does not reference a missing constant. The requirement stands regardless: when call records exist, merge preserves them.

### Conversation history and notes are read-only aggregates

Company "history" is the most recent conversations (bounded list) of member contacts, run through the standard conversation permission filter; company "notes" are the most recent notes written on member contacts. Neither endpoint creates or edits anything — notes are still authored on contacts.

### Authorization

Any account user (agent or admin) can read, create, and update companies and manage membership; **destroy is administrator-only**, matching upstream's policy shape.

## Risks / Trade-offs

- **Denormalization drift** (`company_name` vs `companies.name`) → covered by the sync-on-rename job and strip-on-delete job; both are batched and idempotent.
- **Auto-association false positives** → only business domains qualify (valid, non-disposable, not a known free-mail provider); failures never block contact save.
- **Hot-path write amplification** → activity rollup is throttled; association checks short-circuit on cheap in-memory guards before any account/feature lookup.
- **Clean-room leakage** → implementers work from the spec; upstream EE files may be consulted for behavior questions but expression (naming beyond route-dictated identifiers, comments, i18n strings, SQL phrasing) must not be carried over. Frontend MIT files are exempt from this rule.

## Migration Plan

1. Port the two core migrations (companies jsonb/activity columns; condition-key rename) with fresh timestamps.
2. Land the backend (model, policy, services, jobs, controllers, views) behind the existing routes, extended for nested endpoints.
3. Port the frontend (MIT) including i18n `en/companies.json` and contact-side pieces.
4. Add the merge step for call records (coordinated with the calls capability).
5. Rollback: drop routes/UI additions; companies table remains harmlessly (it already exists).
