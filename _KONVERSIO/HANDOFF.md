# Konversio — Handoff

Snapshot of project state, conventions, and where to pick up next. Companion
to `_KONVERSIO/README.md` (which is the "what + why"); this doc is the
"how, where, and what's next."

Current state: `main` at tag **`v0.2.0-konversio-base`** —
MIT fork of Chatwoot v4.13.0, branded as Konversio, deployed at
https://konversio.migrately.nl, with end-to-end inbound mail working via
Resend. **No AI module yet** — that's Phase 2.

---

## Naming model (READ THIS FIRST — it's been wrong twice already)

| Layer | Name | Status |
|---|---|---|
| Platform / product | **Konversio** | Replaces "Chatwoot" everywhere in code |
| AI module (umbrella, future) | **Pilot** | Replaces Chatwoot's "Pilot". Not built yet. |
| Pilot sub-feature: agent-side chat sidebar | **Copilot** | Chatwoot had this too, same name |
| Pilot sub-feature: customer-facing chatbot | **Autopilot** | (Chatwoot called it "Assistant") |
| Pilot sub-feature: one-click reply draft button | **Briefing** | (Chatwoot: "Reply suggestion") |
| Pilot sub-feature: per-contact persistent memory | **Logbook** | (Chatwoot: "Memories") |
| Human support staff | **Agents** | Unchanged from Chatwoot |
| Chatwoot's old AI brand | **Pilot** | Referenced only as historical context |

**Do not flip Konversio and Pilot.** Konversio is the platform; Pilot is one
feature *inside* Konversio. (Session history: an earlier rename pass
inverted this and we had to redo 300 files. Don't repeat.)

---

## Locations

| What | Where |
|---|---|
| Local working tree | `/Users/rcoenen/Dev/Konversio/` |
| GitHub | `https://github.com/konversio-org/konversio` |
| Live deploy | `https://konversio.migrately.nl` |
| Heroku app | `konversio` (region: EU, stack: heroku-24) |
| Heroku herokuapp URL | `https://konversio-3e5d5fe88a7d.herokuapp.com/` |
| Git remotes | `origin` → konversio-org/konversio (HTTPS, gh credential helper) |
|             | `upstream` → chatwoot/chatwoot (for rebases onto new releases) |
|             | `heroku` → konversio.git |
| Project meta dir | `_KONVERSIO/` (this file, README.md) |

---

## What's running

| Component | Plan / size | Status |
|---|---|---|
| Web dyno | Eco | 1 instance |
| Worker dyno (Sidekiq) | Eco | 1 instance, `SIDEKIQ_CONCURRENCY=5` (lower than default 10 to fit Redis Mini) |
| Postgres | `heroku-postgresql:essential-0` (~$5/mo) | Linked as `DATABASE_URL` |
| Redis | `heroku-redis:mini` (~$3/mo, 20 conn limit) | Linked as `REDIS_URL` |
| ACM / TLS | Auto-managed | Cert issued for `konversio.migrately.nl` |
| DNS | Cloudflare zone `migrately.nl` | CNAME (web) + MX (inbound mail) for `konversio` subdomain |
| Email outbound | Resend, domain `konversio.migrately.nl` verified for sending | DKIM + SPF in place |
| Email inbound | Resend, domain `receiving=enabled` (PATCH'd via API) | MX → SES inbound → Resend → webhook |
| Object storage | S3-compatible (env from support.migrately.nl) | Used for ActionMailbox attachments + ActiveStorage |
| Mail SMTP outbound | Mailtrap (`live.smtp.mailtrap.io`) | From `no-reply@migrately.nl` |

**Monthly hosting cost (approx):** ~$15 — web Eco free, worker Eco free,
Postgres essential-0 $5, Redis mini $3, plus Resend free tier, plus Cloudflare
free, plus S3 reads. Cheap.

---

## Critical config (Heroku env vars)

All set on `konversio` app. None of these live in the repo. Names only:

- `RAILS_ENV`, `RACK_ENV`, `NODE_OPTIONS`, `INSTALLATION_ENV`,
  `REDIS_OPENSSL_VERIFY_MODE=none` — base Rails/Heroku
- `SECRET_KEY_BASE`, `SECRET_TOKEN` — unique per app
- `FRONTEND_URL=https://konversio.migrately.nl`
- `SIDEKIQ_CONCURRENCY=5` — tuned to fit Redis Mini connection limit
- `RESEND_API_KEY`, `RESEND_WEBHOOK_SECRET` — Resend outbound + inbound webhook
- `SMTP_*`, `MAILER_*`, `RAILS_INBOUND_EMAIL_*` — copied from support.migrately.nl
- `STORAGE_*` (7 vars) — S3-compatible storage
- `APP_*`, `DB_*` — legacy Laravel-style vars left over from the support-migrately-nl bulk copy. Harmless; Pilot doesn't read them. Can be pruned later.

When Pilot lands, expect these to be added (matching `PILOT_*` naming):

- `PILOT_OPEN_AI_API_KEY`
- `PILOT_OPEN_AI_ENDPOINT`
- `PILOT_OPEN_AI_MODEL`
- `PILOT_OPEN_AI_API_PROVIDER` (`openai_compatible` for non-OpenAI providers)
- `PILOT_EMBEDDING_MODEL`, `PILOT_EMBEDDING_DIMENSIONS`
- `PILOT_OPEN_AI_TRANSLATION_MODEL`
- `PILOT_FIRECRAWL_API_KEY`

---

## Local development

### Stack

Ruby 3.4.4 + Bundler 2.5.16 + Node 20+ + pnpm 10+ + Postgres 16 + Redis.

### One-time setup

```bash
# Use rbenv (installed via Homebrew earlier this session)
rbenv install 3.4.4

# In the repo
cd /Users/rcoenen/Dev/Konversio
bundle config build.pg --with-pg-config=/opt/homebrew/opt/libpq/bin/pg_config
bundle install
pnpm install --frozen-lockfile
```

### Postgres + Redis for local dev

Two Docker containers are spun up under separate ports (to avoid conflicting
with the Migrately Postgres on 5432):

- `chatwoot-test-pg` on `localhost:5433`
- `chatwoot-test-redis` on `localhost:6380`

```bash
# Start them
docker start chatwoot-test-pg chatwoot-test-redis
# Or recreate if missing:
# docker run -d --name chatwoot-test-pg -p 5433:5432 -e POSTGRES_PASSWORD= -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_USER=postgres pgvector/pgvector:pg16
# docker run -d --name chatwoot-test-redis -p 6380:6379 redis:alpine
```

### Run the app locally

```bash
POSTGRES_HOST=localhost POSTGRES_PORT=5433 POSTGRES_USERNAME=postgres POSTGRES_PASSWORD= POSTGRES_DATABASE=konversio_dev \
REDIS_URL=redis://localhost:6380 \
RAILS_ENV=development SECRET_KEY_BASE=local_dev FRONTEND_URL=http://localhost:3001 PORT=3001 \
bundle exec rails server -p 3001 -b 0.0.0.0
```

For asset hot-reload, in another terminal:

```bash
pnpm dev   # vite dev server on 5173
```

### Local pre-deploy check (catches Vite errors before pushing)

```bash
SECRET_KEY_BASE=local_build RAILS_ENV=production NODE_OPTIONS=--max-old-space-size=4096 \
bundle exec rails assets:precompile
```

This runs the same Vite + Sprockets pipeline Heroku runs at release. **Run
this before every `git push heroku main`** — it caught 3+ Vite errors this
session that would otherwise have cost 5-min Heroku build cycles each.

---

## Deploy

```bash
git push origin main      # GitHub
git push heroku main      # Heroku (triggers Heroku build + release)
```

Heroku release phase runs `bundle exec rails db:chatwoot_prepare` which
handles migrations + seeds idempotently. (Yes, the task is still named
`db:chatwoot_prepare`; not renamed because it's referenced in `Procfile` and
minimal-fork doctrine = don't touch what's not blocking.)

Watch the build / boot logs:

```bash
heroku logs -t -a konversio --source app
```

---

## Repo structure (Konversio-specific bits)

Stock Chatwoot CE layout with these meaningful additions / changes:

| Path | What |
|---|---|
| `_KONVERSIO/` | Konversio project notes — `README.md` (manifesto + roadmap), `HANDOFF.md` (this file) |
| `lib/konversio_*.rb` | Renamed from `lib/chatwoot_*.rb` (5 files: app, captcha, exception_tracker, hub, markdown_renderer) |
| `config/application.rb` | `module Konversio` (was `module Chatwoot`) |
| `config/routes.rb` | Adds `mount ActionMailbox::Resend::Engine, at: '/rails/action_mailbox/resend'` |
| `Gemfile` | + `actionmailbox-resend`, + `svix`, + `fiddle` (Ruby 3.4 deprecation silencer) |
| `LICENSE` | Pure MIT, "Copyright (c) 2026 Konversio. Based on Chatwoot v4.13.0 (MIT)." |
| `enterprise/` | **Deleted.** Chatwoot Enterprise License code, can't be redistributed. |
| `app/javascript/dashboard/api/pilot/` | **Deleted.** Frontend for the Enterprise Pilot API. |
| `app/javascript/dashboard/components-next/pilot/` | **Deleted.** Pilot UI components (61 of them). |
| `app/javascript/dashboard/routes/dashboard/pilot/` | **Deleted.** |
| `app/javascript/dashboard/store/pilot/` | **Deleted.** |
| `app/javascript/dashboard/composables/usePilot.js` | **Stubbed** — returns inactive state |
| `app/javascript/dashboard/composables/useCopilotReply.js` | **Stubbed** |
| `app/javascript/dashboard/composables/useLabelSuggestions.js` | **Stubbed** |
| `lib/pilot/*` (services like `reply_suggestion_service.rb`) | **Kept** — MIT, will be wrapped by Pilot in Phase 2 |
| `custom/app/services/custom/pilot/` | **Doesn't exist yet** — Phase 2 scaffolding goes here |

---

## Inbound email — how it actually flows

```
sender's MUA
  → MX lookup for konversio.migrately.nl  (Cloudflare-served)
  → 10 inbound-smtp.eu-west-1.amazonaws.com  (AWS SES, Resend's inbound infra)
  → Resend captures (only because capabilities.receiving=enabled for this domain)
  → POST https://konversio.migrately.nl/rails/action_mailbox/resend/inbound_emails
  → svix verifies the request signature against RESEND_WEBHOOK_SECRET
  → ActionMailbox::Resend::InboundEmailsController#create  (from actionmailbox-resend gem)
  → ActionMailbox::InboundEmail row inserted
  → S3 upload of the raw email
  → Sidekiq enqueues ActionMailbox::RoutingJob
  → worker dyno picks it up, downloads from S3, matches against an Inbox
  → if a Channel::Email inbox matches the `to:` address, Conversation+Contact+Message created
  → ActionCableBroadcastJob pushes "conversation.created" + "message.created" over WebSocket
  → dashboard at /app/accounts/1/conversations updates live
```

### Things that have to be set up for new domains

1. Verify domain in Resend (sending) — DKIM + SPF auto-added to DNS by Resend.
2. **PATCH `/domains/{id}` with `capabilities.receiving=enabled`** via Resend API — sending verification does NOT auto-enable inbound. **This was the killer gotcha** — domain shows "verified" in Resend UI but inbound silently drops if `receiving=disabled`.
3. Add MX record in Cloudflare → `10 inbound-smtp.eu-west-1.amazonaws.com`.
4. Add webhook in Resend dashboard → `https://<host>/rails/action_mailbox/resend/inbound_emails`, copy the `whsec_*` signing secret.
5. Set `RESEND_WEBHOOK_SECRET` on the Heroku app.
6. Create an Email inbox in Konversio dashboard (`/app/accounts/1/settings/inboxes/new/email`) with the exact `to:` address you want to receive at — otherwise ActionMailbox routes nothing and the email is silently dropped after 30 days (IncinerationJob).

---

## Operational gotchas / lessons from setup

| Issue | Cause | Fix |
|---|---|---|
| Heroku push fails at `pnpm install --frozen-lockfile` | Mass-rename pass changed `@chatwoot/*` npm package names (they're real published packages, can't be renamed) | Always revert any rename that touches `@chatwoot/ninja-keys`, `@chatwoot/prosemirror-schema`, `@chatwoot/utils` in `package.json` |
| Vite build fails locally / on Heroku with "Could not load X" | Strip pass over-deleted a shared file (`globalConfig.js`) or stubbed import target | `git show <upstream-tag>:path/to/file > path/to/file` to restore from upstream |
| Sed-based rename pass mangles unrelated words | BSD sed doesn't honor `\b` word boundary; substring matches like `copilot` → `cokonversio` slip through | Always run `grep -rn "<new-name>[a-z]\|[a-z]<new-name>"` after any rename pass to find substring damage |
| `Redis::CannotConnectError: unexpected eof while reading` on rediss:// connections | Heroku Redis Mini has 20-connection limit; Sidekiq default concurrency 10 + ActionCable + web dyno easily blows past it | Set `SIDEKIQ_CONCURRENCY=5` (saves ~5 connections), or upgrade Redis to `premium-0` (~$15/mo, 40 conns) |
| Inbound email accepted by SES but no webhook fires | Resend domain has `capabilities.receiving=disabled` (separate from sending verification) | `curl -X PATCH https://api.resend.com/domains/<id> -d '{"capabilities":{"receiving":"enabled"}}'` |
| `heroku config:set <SECRET>` shows old value in CLI output | Claude Code transcript-safety filter detects secret-shape in command line and shows the prior value | Use a local bash script that prompts for the secret via `read -rsp` so it never enters the CLI command line directly |
| `ChatwootApp` uninitialized constant at login (500 on POST /auth/sign_in) | Rename pass missed view/jbuilder/migration files when renaming `ChatwootApp` → `KonversioApp` | Grep `ChatwootApp` across `app/views/**/*.jbuilder`, `app/views/**/*.erb`, `db/migrate/**/*.rb`, `app/helpers/**/*.yml` after any module rename |

---

## What's NOT done (Phase 2 = Pilot AI module)

Per the locked-in plan in `_KONVERSIO/README.md`, the AI layer lives in:

```
custom/
└── app/services/custom/pilot/
    ├── pilot_service.rb          base class, LLM routing
    ├── briefing_service.rb       one-click reply draft (start here)
    ├── copilot/                  agent-side chat sidebar
    ├── autopilot/                customer-facing chatbot
    ├── logbook/                  per-contact memory
    └── tools/                    pluggable tool framework
```

### Suggested build order

1. **Briefing** (smallest, contained, daily useful for Migrately-as-customer-zero):
   - Port `lib/llm/config.rb` + `lib/llm/models.rb` + `config/initializers/ai_agents.rb` from `support.migrately.nl-upgrade`, renaming `PILOT_*` → `PILOT_*`
   - Add `custom/app/services/custom/pilot/briefing_service.rb` (mirrors `lib/pilot/reply_suggestion_service.rb` MIT code, parameterized for Pilot config)
   - Add an API endpoint `POST /api/v2/konversio/pilot/briefings` that takes a conversation_id and returns a draft
   - Patch Vue composer to show a "Get Briefing" button when `pilot_enabled` on the account
2. **Copilot** (the chat sidebar — bigger UX work)
3. **Logbook** (per-contact memory — needs DB schema + extraction job)
4. **Autopilot** (customer-facing — biggest, needs Agent Bot pattern + handover logic)
5. **Tools framework** (pluggable, do once Autopilot exists since that's the main consumer)

### Validated LLM provider for EU residency

**Scaleway + Mistral Small 3.2 24B** verified in the other fork during this
session — 0.5s LLM round-trip, ~0.95s end-to-end, fluent Dutch, no prompt
hacks needed. Recommended as Pilot's EU-first default.

Alternative providers (all OpenAI-compatible, all tested in the other fork):
Nebius, Mistral La Plateforme, Groq, Ollama (local), Anthropic (via proxy),
Google Gemini (via proxy).

### Source patches to port

`support.migrately.nl-upgrade` (the user's other Chatwoot fork) has these
relevant commits that should be cherry-picked / re-applied to Konversio:

```
GlobalConfigService refactor — Pilot config reads env first then DB
OpenAI-compatible provider patches — supports any /v1/chat/completions backend
embedding_dimensions param — for embedding model truncation (1536-dim pgvector)
TranslateQueryService model config — language-matching infrastructure
```

(Rename `PILOT_*` → `PILOT_*` everywhere as you port. Keep `lib/pilot/*`
service files in place for now — Pilot will wrap them, not replace them.)

---

## Followups (not blocking Phase 2)

- **Redis upgrade** — Mini → premium-0 (~$15/mo) when load grows past test/single-user volume. Doubles connection limit, adds HA + persistence.
- **Disable old support.migrately.nl Resend webhook** — currently still active alongside konversio's, so every inbound email creates a conversation in BOTH apps. Cut over when confident in Konversio.
- **Prune Laravel-style env leftovers** — `APP_*`, `DB_*` config vars on Heroku are unused by Pilot (copied accidentally from support-migrately-nl bulk import). Safe to delete.
- **Logo + branding polish** — current login page logo says "konversio" in white wordmark but it's a placeholder; needs a real design pass.
- **CI** — no GitHub Actions / lint / rspec on push yet. Worth adding before any external contributors.
- **DMARC** — no `_dmarc.konversio.migrately.nl` TXT record yet. Set `v=DMARC1; p=none; rua=mailto:dmarc@...` to start collecting reports.

---

## How to pick up this work in a future session

1. `cd /Users/rcoenen/Dev/Konversio`
2. `git fetch origin && git checkout main && git pull`
3. Read this file. Then `_KONVERSIO/README.md`.
4. Confirm naming model in your head: **Konversio = product, Pilot = AI feature (future).**
5. If working on Phase 2: start with Briefing (smallest, contained, daily useful).
6. If working on infra: see "Followups" above.
7. Pre-deploy: always run `bundle exec rails assets:precompile` locally before pushing to Heroku.
8. Commits: Conventional Commits format. Don't mention Claude in messages.
9. Pushes: `git push origin main` (GitHub) THEN `git push heroku main` (deploy).
