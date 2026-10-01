## Capability: dependency-security-updates

Version parity with upstream's v4.14.2-era security and platform updates for the web server, the OAuth dependency family, and the Vite Ruby toolchain. All targets are MIT-licensed upstream version choices.

---

## ADDED Requirements

### Requirement: Puma at 7.2.x

The application server SHALL be Puma `~> 7.2, >= 7.2.1` (upstream's pinned version), with `config/puma.rb` unchanged unless the major-version upgrade proves a setting incompatible.

#### Scenario: puma 7.2.x serves the app

- Given the Gemfile constrains puma to `~> 7.2, >= 7.2.1`
- When the app boots in container mode
- Then HTTP requests are served, ActionCable connections stream, and no puma configuration errors are logged

#### Scenario: config/puma.rb stays compatible

- Given upstream's `config/puma.rb` is byte-identical between v4.13.0 and v4.18.0
- When puma is upgraded to 7.2.x
- Then Konversio's `config/puma.rb` boots unmodified, or any required change is documented in the PR

---

### Requirement: OAuth dependency family at patched versions

The transitive OAuth dependencies SHALL resolve to oauth 1.1.6, oauth-tty 1.0.8, and oauth2 2.0.22 (upstream's patched versions), via targeted bundle updates rather than new direct Gemfile entries.

#### Scenario: lockfile shows patched versions

- Given `bundle update oauth oauth-tty oauth2` has been run
- When `Gemfile.lock` is inspected
- Then oauth is 1.1.6, oauth-tty is 1.0.8, and oauth2 is 2.0.22

#### Scenario: omniauth flows still work

- Given the bumped OAuth gems
- When the Google and Facebook/Instagram omniauth callback specs run
- Then they pass, including the Rails 7 `allow_other_host` redirect behavior

---

### Requirement: Vite Ruby toolchain at 3.10.x

The Ruby-side Vite integration SHALL resolve to vite_rails 3.10.0 and vite_ruby 3.10.2 (upstream's versions), while the JS-side Vite remains on Konversio's existing Vite 6 line (≥ 6.4.2), which is already ahead of upstream.

#### Scenario: dev server and precompile work after bump

- Given vite_rails 3.10.0 and vite_ruby 3.10.2
- When `bin/vite dev` runs in host mode and `assets:precompile` runs in container mode
- Then HMR works in development and the production build completes successfully

#### Scenario: no JS-side downgrade

- Given Konversio's `package.json` already ranges vite `^6.3.6`/`^6.4.3` and `@vitejs/plugin-vue` `^6.0.1`
- When the toolchain bump completes
- Then vite resolves to ≥ 6.4.2 and `@vitejs/plugin-vue` is NOT downgraded to upstream's `^5.2.4`
