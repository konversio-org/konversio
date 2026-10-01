## Capability: rails-7-2-runtime-reconcile

Konversio independently migrated from Rails 7.1.5.2 to 7.2.3.1 (commits `855e076a3`, `2d9a55d35`, `ea4da5f94`, and the `allow_other_host` redirect fixes, June 2026) — upstream shipped the equivalent in v4.17.0. This capability covers verifying that migration is complete and reconciling the remaining deltas from upstream's upgrade stack. It is NOT a fresh upgrade.

---

## ADDED Requirements

### Requirement: Rails runtime pinned at 7.2.3.1

The application SHALL run on Rails 7.2.3.1, with `Gemfile.lock` resolving rails, actionpack, activerecord, and railties to 7.2.3.1, and the Gemfile retaining the `~> 7.2` constraint.

#### Scenario: lockfile resolves to 7.2.3.1

- Given a fresh `bundle install`
- When `Gemfile.lock` is inspected
- Then rails, actionpack, activerecord, and railties all report version 7.2.3.1

#### Scenario: schema stamp reflects Rails 7.2

- Given the application database
- When `db/schema.rb` is regenerated via `bundle exec rails db:schema:dump`
- Then the schema is stamped `define(version: ...) [7.2]`-compatible
- And all hairtrigger-managed triggers are present in the dump

#### Scenario: application boots and suite passes on 7.2

- Given the reconciled Gemfile.lock
- When the app boots in host mode and container mode and `bundle exec rspec` runs
- Then boot succeeds and the suite is green

---

### Requirement: rails-i18n available for backend localization

The application SHALL include the `rails-i18n` gem (`~> 7.0`, matching upstream v4.18.0) so backend date, time, number, and pluralization data is available for enabled locales.

#### Scenario: rails-i18n provides data for new locales

- Given `rails-i18n` is bundled
- When backend translations are looked up for locales uz, sl, and et
- Then date/time formats and pluralization rules resolve without falling back to English for those keys

---

### Requirement: devise-secure_password source reconciled

The dependency on `devise-secure_password` SHALL be evaluated against upstream's rubygems pin (2.2.1) instead of the Chatwoot git fork, and the Gemfile SHALL record whichever source passes equivalence checks.

#### Scenario: pinned gem adopted when equivalent

- Given upstream pins `devise-secure_password` to rubygems 2.2.1
- When password-policy behavior (validation, expiry, denial of reuse) is compared between the git fork and the 2.2.1 gem
- Then the Gemfile uses the 2.2.1 rubygems pin if behavior is equivalent, or documents the divergence if the fork must stay

---

### Requirement: No fresh Rails upgrade work

This change SHALL NOT re-apply upstream's Rails 7.2 migration commits or replace application-level Rails 7.2 fixes already landed in Konversio (pool-based `migration_context`, `alias_method` on `User#conversations`, `allow_other_host` redirect handling, hairtrigger 1.3.1).

#### Scenario: existing fixes are preserved

- Given Konversio's Rails 7.2 fixes in git history
- When the reconcile completes
- Then each of those fixes is still present and exercised by the test suite
