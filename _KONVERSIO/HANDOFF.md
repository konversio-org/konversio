# Konversio — Handoff

Snapshot of project state, conventions, and where to pick up next. Companion
to `_KONVERSIO/README.md` (which is the "what + why"); this doc is the
"how, where, and what's next."

Current state: working branch `purge-captain` (not yet merged to `main`)
— MIT fork of Chatwoot v4.13.0, branded as Konversio, deployed base at
https://konversio.migrately.nl. **Phase 2 (Pilot AI module) is now ~70%
built and verified end-to-end against OpenAI / Scaleway.** See
"Phase 2 status (May 2026)" below for the full state.

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

## Phase 2 status (May 2026)

The mega-proposal at `openspec/changes/pilot-full/` defines 10
sub-features. As of the last working session on `purge-captain`:

### Working end-to-end (verified via Chrome MCP + rails runner)

| Sub-feature | What it does | Surface |
|---|---|---|
| **Foundation** | env-first `PILOT_*` config, OpenAI-compatible routing, embedding dim control | `lib/llm/config.rb`, `lib/global_config_service.rb` |
| **Copilot** | agent-side chat drawer with persistent threads + ai-agents SDK runner + 4 in-process tools (search_conversation, get_conversation, get_contact, search_documentation) | Dashboard sidebar drawer |
| **Briefing** | one-click reply draft → fills composer in Reply mode | Sparkle dropdown |
| **Autopilot** | customer-facing chatbot: vector KB retrieval, typing indicator, handover flow, status-lifecycle gating, multilingual | Chat widget |
| **Summary** | conversation summary → fills composer in **Private Note** mode (auto-switch, footgun-safe) | Sparkle dropdown |
| **Follow-up** | 1-3 clarifying questions for the agent | Sparkle dropdown (API works; UI emit currently → void) |
| **Rewrite** | rewrites composer draft in friendly tone | Sparkle dropdown (whole-draft only, no selection toolbar yet) |
| **CSAT analysis** | background job: sentiment / themes / escalation flag on free-text CSAT comment | `pilot_csat_analysis_enabled` |
| **Label suggestion** | background job: populates `conversation.suggested_label_ids` on conversation create | `pilot_label_suggestion_enabled` |

### Built but not user-visible

- **SuggestedLabelChips.vue** — exists, not mounted above label selector.
- **RewriteToolbar.vue** floating selection-based — exists in tree but not mounted; ProseMirror hook needed for the selection version.
- ~~**FollowUp result handler** — emit goes to void; needs ReplyTopPanel listener to insert as chips.~~ Shipped 2026-05-18 (commit `0a4531e4c`) as an in-menu picker inside `PilotActionsMenu.vue` — the sparkle popover swaps to a "Pick a follow-up to ask" panel after the API call, click-to-insert via `INSERT_INTO_RICH_EDITOR`. Design pattern conceptually borrowed from Chatwoot Enterprise Captain's menu→result surface swap.
- **CSAT report aggregation view** — schema columns ready (`pilot_sentiment`, `pilot_themes`, `pilot_escalation_recommended`), no UI card.

### Not started

| Section | Description |
|---|---|
| **4 controllers + admin UI** | Assistants/Documents/Scenarios/Responses CRUD endpoints + dashboard sidebar group. Everything still done via rails console today. |
| **5 Logbook** | Per-contact persistent memory, extraction job, injection into Briefing/Copilot/Autopilot context |
| **6 Tools** | Pluggable HTTP tool framework for Autopilot custom tools |
| **7 Telemetry** | `pilot_events` table, activity log view, sensitive-payload redaction. Note: event dispatch (`dispatch_event(:foo)`) is already plumbed everywhere; just needs a persister. |
| **8 Onboarding** | First-time admin wizard with provider config + connection test |
| **9 Autoresolve** | Scheduled job to auto-resolve idle Autopilot conversations |

### Validated providers

- **OpenAI** — `gpt-4o-mini` + `text-embedding-3-small` is the current dev default. Set via `PILOT_OPEN_AI_API_KEY` / `PILOT_OPEN_AI_MODEL` / `PILOT_EMBEDDING_MODEL`.
- **Scaleway + Mistral Small 3.2 24B** — EU-residency option, verified working in earlier session. Use `PILOT_OPEN_AI_API_PROVIDER=openai_compatible` + Scaleway endpoint.

### Demo flow that works today

1. Open `http://localhost:3000/widget?website_token=<token>` → type "When are you open?" → bot answers from KB
2. Type "I want to speak to a human" → bot says "Transferring..." → conversation status → `pending` → bot stops responding (no loop)
3. Login at `/app/accounts/1/conversations` → open the conversation → click sparkle → Summarize → composer switches to Private Note + markdown summary lands
4. Multi-turn agent-side: click Pilot icon in sidebar → Copilot drawer opens → "How many open conversations?" → bot calls `search_conversation` tool → answers with real data

### Branch state

- **`main`** — last released; doesn't have Phase 2.
- **`purge-captain`** — current working branch, all Phase 2 commits. Not yet rebased/merged to main. Recommend tagging `v0.3.0-pilot-mvp` and merging once the next round of UI mount work is done (Section 10 follow-ups + Section 4 admin UI).

---

## Dev-infra lessons from Phase 2 sessions (read before changing Vue/JS!)

Konversio's Docker + Vite + Rails dev stack is fragile in ways that
upstream Chatwoot mostly ignores. These cost real hours in past sessions;
read them before you change Vite config or spawn an agent that smoke-tests
in the browser.

### 1. The three Vite knobs that must agree

| Setting | File | Wrong value → what breaks |
|---|---|---|
| `host` | `config/vite.json` | Default `::1` → Rails container can't reach Vite. Must be `0.0.0.0`. |
| `autoBuild` | `config/vite.json` | `true` → Rails inline-compiles on cold widget loads → ENOMEM crash; `false` → manifest must exist, else 404 cascade on all assets. We run with `false`. |
| `usePolling` | `vite.config.ts` server.watch | macOS bind mounts don't fire native fs events into Linux containers, so the watcher must poll. Also `CHOKIDAR_USEPOLLING=true` env var as belt-and-suspenders. |

### 2. Manifest drift between Rails ↔ Vite

Rails reads `public/vite-dev/.vite/manifest.json` **once at boot** and caches
it. Vite rebuilds produce new chunk hashes (e.g. `dashboard-CpUZs8i0.js`).
Rails keeps serving HTML with old hash references → 404 cascade.

**Recovery**: after any Vite full rebuild, also `docker compose restart rails`
so it re-reads the manifest. The polling-watcher setup (lesson 1) avoids
needing manual `bin/vite build` for incremental edits, but the FIRST
build after a clean state still needs the Rails restart.

### 3. HMR is not magical

Vite's HMR pushes updated modules to connected browsers, but:
- **Template-only edits** (text, styles, simple bindings) → HMR works clean.
- **Parent passing new listener/prop to child** (e.g. `@new-event="handler"` on a child mount) → HMR pushes the updated source, but the *mounted Vue vnode props* on the live instance can stay stale. Bug we hit: `onRequestReplyMode` was in compiled source but `inst.vnode.props` on the mounted PilotActionsMenu didn't include it.

**Test**: `inst.vnode.props` via Chrome MCP `evaluate_script` walking up from a DOM element. If listeners are missing, HMR didn't fully apply.

**Recovery**: hard refresh (Cmd+Shift+R), or close-and-reopen tab. Browser navigation between routes ≠ full reload — Vue keeps modules in memory.

### 4. The `vite_javascript_tag` chdir bug → connection pool exhaustion

`vite_javascript_tag` does `Dir.chdir` to read the manifest. **Not thread-safe.**
With multiple Puma threads + concurrent widget requests, the chdir race
throws, the template render aborts, and the AR connection that was checked
out for the request never gets returned. After ~5 cascading failures,
every new request times out at 5s with `ConnectionTimeoutError` — looks
like Rails has hung but it's really pool exhaustion from leaked connections.

**Fix in `purge-captain`**: `config/database.yml` pool = `RAILS_MAX_THREADS * 2`,
plus Puma `before_fork` / `on_worker_boot` hooks that disconnect+reestablish.

### 5. Two different `getCurrentAccount` getters

| Getter | Returns |
|---|---|
| `useMapGetter('getCurrentAccount')` | Agent's account-**membership** stub (id, name, role) — NO `pilot_*` flags |
| `useMapGetter('accounts/getAccount')(accountId)` | Full account JSON including `pilot_*` flags |
| `useAccount()` composable | Wraps the above — **canonical**, use this |

Using the wrong getter compiles fine, runs without error, and silently
evaluates feature gates to `false`. Bug hit: SummarizeButton used the
wrong one, popover never rendered despite all flags being true.

**Rule**: always use `useAccount()` for `pilot_*` flag checks.

### 6. Worktree agents work off stale base

When you spawn an agent with `isolation: "worktree"`, the worktree branch
is created off `purge-captain`'s **current HEAD at spawn time**. If commits
land on `purge-captain` after the agent starts, the worktree is stale.

Hit this 4 times across agents that needed to smoke-test in the running
container — Docker mounts the **main repo path**, not the worktree path, so
the agent has to either:
- Mirror its files to the main repo to test (then revert main on completion), or
- Skip live testing, leave changes uncommitted on worktree, accept that
  the reviewer needs to copy files to main + verify.

The Section 4 backend agent + Summary-mount agent both did the mirror
approach. Both got it right but explained the maneuver in their reports.

**Rule for prompts**: if an agent needs to smoke-test in browser/Docker,
explicitly tell it Docker mounts main, not the worktree, and that it
should mirror to main for the test phase.

### 7. The lint-staged catch-22

`git add foo.vue` → husky pre-commit → eslint on staged files → catches
**pre-existing** lint errors in `foo.vue` from prior contributors → commit
rejected.

Hit this twice. Common pre-existing errors:
- Unused emit declarations (`emits: ['toggleEditorSize', ...]` but never `emit('toggleEditorSize')`)
- Unused props
- Trailing newlines / prettier formatting drift

**Rule**: when touching a file, expect to fix unrelated lint in the same
commit. Or do a separate `chore: fix lint` commit first if it's
substantial.

### 8. Cache layers, in order of depth

When something behaves "stale" in dev mode, peel back in order:

1. Browser HTTP cache → Cmd+Shift+R
2. Vue HMR module cache → close+reopen tab
3. Vite transform cache (in-memory) → `docker compose restart vite`
4. `node_modules/.vite/deps/` → `rm -rf node_modules/.vite && restart`
5. `tmp/cache/vite/last-build-development.json` → `rm` (vite_ruby uses this to decide "skip build")
6. `public/vite-dev/` (the built output Rails serves) → `rm -rf && bin/vite build`
7. Full `docker compose down && up` → nuclear

90% of dev-mode weirdness clears at level 1-2.

### 9. Vue 3 emit name normalization (compiler-level)

When child does `emit('requestReplyMode', val)`, the parent listens via
template attribute `@request-reply-mode="..."`. Vue's compiler converts
this to `onRequestReplyMode` prop on the rendered child vnode.

If you grep compiled output for `request-reply-mode`, you'll find only
source-map text. The actual wiring is `onRequestReplyMode` (camelCase
with `on` prefix). Inspecting `inst.vnode.props` shows `onRequestReplyMode`.

**Rule**: when verifying "is my event listener actually wired in compiled
output?", grep for `on<EventName>` (camelCase, `on`-prefixed), not the
kebab-case template attribute.

### 10. Pre-existing Chatwoot quirks (not our fault, but ignore them)

These show up in console / logs but are upstream Chatwoot dev-mode issues:

- `Multiple versions of Lit loaded` — webcomponent dedup issue upstream
- `POST .../widget/conversations/toggle_typing 404` on every keystroke before first message — controller `before_action :render_not_found_if_empty` bails when no conversation exists. We replaced the 404 with a silent 200 no-op for `toggle_typing` specifically.
- `chdir` warnings under load — see lesson 4
- `[@vue/compiler-sfc] ::v-deep usage as a combinator has been deprecated` — upstream component CSS

**Rule**: don't chase these in your session. File them as "pre-existing
upstream noise" and move on.

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
2. `git fetch origin && git checkout purge-captain && git pull` (NOT main — Phase 2 lives on `purge-captain` until it's tagged and merged)
3. Read this file end-to-end. Especially "Phase 2 status" and "Dev-infra lessons".
4. Confirm the naming model: **Konversio = product, Pilot = AI module, Copilot/Autopilot/Briefing/Summary/etc = sub-features inside Pilot.** Do not flip them.
5. Bring up the stack: `docker compose up -d` then `until curl -fs http://localhost:3000/app/login >/dev/null; do sleep 2; done`. The full set is `postgres, redis, rails, sidekiq, vite, mailhog, base`.
6. Smoke-test a known-good feature first to confirm your environment isn't broken before touching code: open `http://localhost:3000/widget?website_token=<token>` (find token via `rails runner "puts Account.first.inboxes.first.channel.website_token"`), type "what are your hours?", expect a Pilot Autopilot reply in ~5s.

### If you're picking up Phase 2

The natural next chunks, in rough priority order:

| Chunk | Why | Size |
|---|---|---|
| **Section 10 follow-ups** (mount FollowUpSuggestionsButton + RewriteToolbar selection-based + SuggestedLabelChips + CSAT report card) | Surface work that's already-built backend | Half-day each |
| **Section 4 admin UI** (controllers + Vue components for Assistants/Documents/Scenarios CRUD) | Removes the "manage from rails console only" limitation | Multi-day |
| **Section 7 Telemetry** (`pilot_events` persister + activity log view) | All events are dispatched already; just need a persister + read view. High value for debugging Pilot in production. | Half-day |
| **Section 5 Logbook** | Per-contact memory injected into all bots — biggest UX leap | Multi-day |
| **Section 6 Tools** | Pluggable HTTP tools for Autopilot | Multi-day |
| **Section 8 Onboarding wizard** | First-time admin setup | Day |
| **Section 9 Autoresolve** | Scheduled job, small surface | Half-day |

### Commit/deploy discipline

- Conventional Commits (`feat(pilot-*)`, `fix(dev)`, `chore(brand)`).
- Don't mention Claude in messages.
- Pre-deploy: `bundle exec rails assets:precompile` locally before pushing to Heroku (catches most build errors). With the live-HMR polling now in place this is rarely needed during dev itself.
- Pushes: `git push origin purge-captain` for now. Tag + merge to `main` (`git push heroku main`) only once the next round is stable and you want it on prod.

### Spawning agents

When you spawn agents for Phase 2 work:
- Use `isolation: "worktree"` for clean isolation.
- **Brief them that Docker mounts the main repo, not the worktree.** If they need to smoke-test, they must mirror files to the main repo and revert after.
- Tell them the latest commit on the base they're targeting, so they can verify they have it (multiple agents hit "stale base" issue).
- Include "use Chrome MCP for browser verification, not just rails-runner smoke tests" when UI is involved — pure backend tests miss surface-wiring bugs.
