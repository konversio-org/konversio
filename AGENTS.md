# Chatwoot Development Guidelines

## Dev environments

Two modes are supported. **Host mode is the default for daily work.**

### Host mode (default — fast)

Rails + Sidekiq run natively on macOS via rbenv. Postgres, Redis, Mailhog, and Vite stay in Docker (services only). Page reloads in ms instead of seconds; native FSEvents → reliable autoload; IDE Ruby tooling works without bridge tricks. `.env.development.local` (git-ignored) overrides container hostnames with `localhost` for the host process.

```bash
# One-time setup
brew install libpq libvips imagemagick
bundle config build.pg --with-pg-config=$(brew --prefix libpq)/bin/pg_config   # only if pg gem fails
rbenv install $(cat .ruby-version)
bundle install
pnpm install

# Daily
docker compose up -d postgres redis mailhog vite   # services only
overmind start -f Procfile.host                    # Rails + Sidekiq on host
```

App at `http://localhost:3000`. Vite HMR at `http://localhost:3036`.

### Container mode (full Linux parity)

Everything in Docker. Slower (mount + watcher overhead) but matches production exactly. Use for: pre-deploy smoke tests, debugging gem issues that only manifest on Linux, onboarding contributors who don't want Ruby on their Mac.

```bash
docker compose up -d
```

App at `http://localhost:3000`. Containers: `konversio-{rails,sidekiq,vite,postgres,redis,mailhog}-1`.

### Container mode troubleshooting — the 30-second heuristic

When something is broken in container mode, the temptation is to blame Docker / the file watcher / bootsnap / Vite Ruby. **Resist that for 30 seconds and try the boring stuff first.** Past incidents in this repo cost hours because the platform got blamed when the actual bug was a one-line missing registration. Order of operations:

1. **Differential diagnosis.** If a sibling works and the new thing doesn't, `grep` the wiring of both and diff. The bug is in the diff. Example: when `pilot_open?` was undefined in views but `settings_open?` worked, `grep helper_method app/controllers/super_admin/application_controller.rb` revealed the missing entry in 30 seconds.
2. **Direct introspection, not theory.** `docker compose exec rails bundle exec rails runner 'puts SomeController._helpers.instance_methods.include?(:foo)'` answers in 5 seconds what an hour of theorizing about "Rails autoload reliability" can't. Chrome DevTools MCP can inspect live DOM / network / globals on the running browser.
3. **Read the error message literally, including the unfamiliar parts.** `ActionView::Template::Error (undefined method 'X' for an instance of #<Class:0x...>)` — that anonymous Class is the view context, not the controller. The bit you don't recognize is the bit that names the answer.
4. **Time-box hypotheses.** If a fix doesn't make HTTP 500 → HTTP 200 on the next request, the theory is wrong. Don't layer cache clears, restarts, and env tweaks on top. Transient false positives (puma's worker pool emptying between failing requests) are not validation.
5. **Suspect your own diff before the substrate.** The platform has been stable for years; your edit from five minutes ago is far more likely to be the bug.

Genuine platform-level gotchas DO exist in this stack and are worth knowing — they're documented in "Common commands" below (`.env` reload via `--force-recreate`, polling watcher, `VITE_RUBY_HOST=vite` for Rails-side dev server detection). But reach for them after step 1–5, not before.

## Common commands

- **Tail logs**: `docker compose logs -f rails` (container mode) / Overmind's own pane (host mode)
- **Shell into rails container**: `docker compose exec rails bash`
- **Reload .env in containers** (container mode only): `docker compose up -d --force-recreate rails sidekiq` — `docker compose restart` does NOT re-read the .env file.
- **Code auto-reload**: This repo uses `config.file_watcher = ActiveSupport::FileUpdateChecker` (polling) in `config/environments/development.rb`. The evented watcher (`listen` → rb-inotify) is unreliable across the macOS↔Linux bridge in Docker/OrbStack — see `rails/rails#40332`, `docker/for-mac#2375`. **Do NOT switch back to `EventedFileUpdateChecker`.** Host mode would tolerate the evented watcher but polling is harmless there. Initializer/Gemfile/route changes always need a Rails restart (`overmind restart backend` in host mode, `docker compose restart rails` in container mode).
- **Seed Local Test Data**: `bundle exec rails db:seed` (host) / `docker compose exec rails bundle exec rails db:seed` (container)
- **Seed Search Test Data**: `bundle exec rails search:setup_test_data` (host) / prepend `docker compose exec rails ` (container)
- **Seed Account Sample Data**: `Seeders::AccountSeeder` is available as an internal utility and is exposed through Super Admin `Accounts#seed`, but can be used directly in dev workflows too:
  - UI path: Super Admin → Accounts → Seed (enqueues `Internal::SeedAccountJob`).
  - CLI path: `bundle exec rails runner "Internal::SeedAccountJob.perform_now(Account.find(<id>))"` (host) / prepend `docker compose exec rails ` (container).
- **Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix` (always on host)
- **Lint Ruby**: `bundle exec rubocop -a` (host) / `docker compose exec rails bundle exec rubocop -a` (container)
- **Test JS**: `pnpm test` / `pnpm test:watch`
- **Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb` (host) / `docker compose exec rails bundle exec rspec spec/path/to/file_spec.rb` (container)
- **Single Test**: append `:LINE_NUMBER` to the spec path.
- **Ruby Version**: managed via `rbenv` per `.ruby-version`. `eval "$(rbenv init - zsh)"` is already in `~/.zshrc`.
- Always prefer `bundle exec` for Ruby CLI tasks (rspec, rake, rubocop, etc.).

## Code Style

- **Ruby**: Follow RuboCop rules (150 character max line length)
- **Vue/JS**: Use ESLint (Airbnb base + Vue 3 recommended)
- **Vue Components**: Use PascalCase
- **Events**: Use camelCase
- **I18n**: No bare strings in templates; use i18n
- **Error Handling**: Use custom exceptions (`lib/custom_exceptions/`)
- **Models**: Validate presence/uniqueness, add proper indexes
- **Type Safety**: Use PropTypes in Vue, strong params in Rails
- **Naming**: Use clear, descriptive names with consistent casing
- **Vue API**: Always use Composition API with `<script setup>` at the top

## Styling

- **Tailwind Only**:  
  - Do not write custom CSS  
  - Do not use scoped CSS  
  - Do not use inline styles  
  - Always use Tailwind utility classes  
- **Colors**: Refer to `tailwind.config.js` for color definitions

## General Guidelines

- MVP focus: Least code change, happy-path only
- No unnecessary defensive programming
- Ship the happy path first: limit guards/fallbacks to what production has proven necessary, then iterate
- Prefer minimal, readable code over elaborate abstractions; clarity beats cleverness
- Break down complex tasks into small, testable units
- Iterate after confirmation
- Avoid writing specs unless explicitly asked
- Remove dead/unreachable/unused code
- Don’t write multiple versions or backups for the same logic — pick the best approach and implement it
- Prefer `with_modified_env` (from spec helpers) over stubbing `ENV` directly in specs
- Specs in parallel/reloading environments: prefer comparing `error.class.name` over constant class equality when asserting raised errors

## Codex Worktree Workflow

- Use a separate git worktree + branch per task to keep changes isolated.
- Keep Codex-specific local setup under `.codex/` and use `Procfile.worktree` for worktree process orchestration.
- The setup workflow in `.codex/environments/environment.toml` should dynamically generate per-worktree DB/port values (Rails, Vite, Redis DB index) to avoid collisions.
- Start each worktree with its own Overmind socket/title so multiple instances can run at the same time.

## Commit Messages

- Prefer Conventional Commits: `type(scope): subject` (scope optional)
- Example: `feat(auth): add user authentication`
- Don't reference Claude in commit messages

## PR Description Format

- Start with a short, user-facing paragraph describing the product change.
- Add a `Closes` section with relevant issue links (GitHub, Linear, etc.).
- For feature PRs, add `How to test` from a product/UX standpoint.
- For bugfix PRs, use `How to reproduce` when helpful.
- Optionally add a `What changed` section for implementation highlights.
- Do not add a `How this was tested` section listing specs/commands.

## Project-Specific

- **Translations**:
  - Only update `en.yml` and `en.json`
  - Other languages are handled by the community
  - Backend i18n → `en.yml`, Frontend i18n → `en.json`
- **Frontend**:
  - Use `components-next/` for message bubbles (the rest is being deprecated)

## Ruby Best Practices

- Use compact `module/class` definitions; avoid nested styles

## Fork Status

- Konversio is a hard fork of Chatwoot v4.13.0 — no upstream tracking, 100% MIT, self-hosted only.
- The `enterprise/` overlay and Captain AI have been removed; there is no OSS/Enterprise split to preserve.
- Captain has been renamed to `Pilot::` throughout (namespace, DB tables, identifiers, frontend, specs).
- Edit core files freely — no `prepend_mod_with` dance, no mirror-edits, no `spec/enterprise`.
- **Pilot was built clean-room.** See [`FORK_STRATEGY.md`](./FORK_STRATEGY.md) for the full methodology. Critical rule for any work on Pilot: **do not resurrect deleted `enterprise/captain/*` files from git history to reference when extending Pilot.** No `git show 461d6ab36^:enterprise/captain/...`, no pasting that source into any tool. The Chinese Wall holds only if no protected expression flows in.

## Branding / White-labeling note

- For user-facing strings that currently contain "Chatwoot" but should adapt to branded/self-hosted installs, prefer applying `replaceInstallationName` from `shared/composables/useBranding` in the UI layer (for example tooltip and suggestion labels) instead of adding hardcoded brand-specific copy.
