## Capability: widget-and-dashboard-locales

Uzbek added as a full-stack language (upstream v4.16.0), Slovenian added as a full-stack language (upstream v4.17.0), and Estonian enabled in the chat widget (upstream v4.18.0). All locale content is MIT-licensed upstream community translation ported verbatim. Slovenian and Estonian translation files already exist on disk in Konversio (inherited from the v4.13.0 fork base) but are not registered in any i18n registry.

Per repo convention, only `en.yml`/`en.json` are maintained in-repo; strings unique to Konversio (including all Pilot strings) fall back to English in these locales.

---

## ADDED Requirements

### Requirement: Uzbek selectable as an account locale

Uzbek (`uz`) SHALL be registered in `LANGUAGES_CONFIG` (`config/initializers/languages.rb`) as an enabled language at the next unused index (42), with ISO 639-3 code `uzb`, so it flows into `Rails.configuration.i18n.available_locales` and the `Account.locale` enum without renumbering existing entries.

#### Scenario: uz appears in available locales

- Given the updated `LANGUAGES_CONFIG`
- When the application boots
- Then `:uz` is present in `Rails.configuration.i18n.available_locales`
- And `Account` records can be saved with locale `uz`

#### Scenario: existing locale indexes unchanged

- Given existing accounts with non-English locales stored via the enum
- When Uzbek and Slovenian entries are appended
- Then every pre-existing `LANGUAGES_CONFIG` index maps to the same language as before

---

### Requirement: Slovenian selectable as an account locale

Slovenian (`sl`) SHALL be registered in `LANGUAGES_CONFIG` as an enabled language at the next unused index (43), with ISO 639-3 code `slv`, reusing the on-disk translation files.

#### Scenario: sl appears in available locales

- Given the updated `LANGUAGES_CONFIG`
- When the application boots
- Then `:sl` is present in `Rails.configuration.i18n.available_locales`
- And `Account` records can be saved with locale `sl`

---

### Requirement: Uzbek translation files present across all four apps

Uzbek translations SHALL exist for the Rails backend (`config/locales/uz.yml`), the dashboard (`app/javascript/dashboard/i18n/locale/uz/`), the chat widget (`app/javascript/widget/i18n/locale/uz.json`), and the survey app (`app/javascript/survey/i18n/locale/uz.json`), ported verbatim from upstream.

#### Scenario: backend resolves Uzbek strings

- Given `config/locales/uz.yml` is present
- When a backend translation (e.g. a mailer subject) is looked up with locale `uz`
- Then the Uzbek string is returned, with English fallback for keys the file does not define

#### Scenario: widget renders in Uzbek

- Given an inbox whose widget locale is `uz`
- When a visitor opens the chat widget
- Then widget UI strings render in Uzbek where translations exist

---

### Requirement: i18n registries wire uz, sl, and et

The JavaScript i18n registries SHALL register the new locales exactly matching upstream's v4.18.0 state: widget (`app/javascript/widget/i18n/index.js`) registers `et`, `sl`, and `uz`; dashboard (`app/javascript/dashboard/i18n/index.js`) registers `et`, `sl`, and `uz`; survey (`app/javascript/survey/i18n/index.js`) registers `sl` and `uz` only.

#### Scenario: widget locale selection includes Estonian

- Given the widget i18n registry
- When a widget is configured with locale `et`
- Then Estonian widget translations render (the file exists on disk; registration is the change)

#### Scenario: survey has no Estonian

- Given upstream ships no Estonian survey locale at v4.18.0
- When the survey i18n registry is inspected
- Then `et` is not registered and survey locale selection falls back per existing behavior

---

### Requirement: English fallback for Konversio-specific strings

Translations unique to Konversio (rebranded copy, Pilot AI strings) SHALL NOT be translated into uz/sl/et as part of this change; the i18n fallback chain SHALL render them in English.

#### Scenario: Pilot string falls back to English

- Given an account using locale `uz`
- When a UI surface renders a Pilot-specific string that exists only in `en.json`
- Then the English string is displayed and no missing-translation error is raised
