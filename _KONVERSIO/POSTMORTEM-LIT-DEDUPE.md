# Post-mortem: the Lit dedupe rabbit hole

Date: 2026-05-18
Branch: `purge-captain`
Session goal: ship favicon-badge notification on bot→agent handoff
Time spent on the goal: ~30 min
Time spent on a self-inflicted detour: ~3 hours

This is a write-up of how a small UX fix turned into a multi-hour
infrastructure battle, what specifically went wrong, and the rules we're
adopting so it doesn't happen again.

---

## What we set out to do

The bot decides to hand off to a human. Default Policy auto-assigns the
conversation to an agent. The dashboard inbox surfaces the conversation
correctly, but the **favicon doesn't flip to the badged variant** — the
agent has no peripheral signal that work just landed on them.

Server-side `assignee.changed` is dispatched correctly. The frontend
needed a tiny hook: when the new assignee is the current user, call
`showBadgeOnFavicon()` (which Chatwoot already ships and which works for
normal incoming messages).

Total surface area of the actual feature work:
- `app/javascript/dashboard/helper/AudioAlerts/DashboardAudioNotificationHelper.js` — add `onAssigneeChanged(conversation)` method
- `app/javascript/dashboard/helper/actionCable.js` — wire the existing `assignee.changed` cable event to call it

Two files. About 25 lines. Committed as `2d7efa65b fix(notifications):
trigger favicon badge + audio on assignee change`. **That commit is
correct and intact.**

---

## How it went sideways

Along the way the browser console kept showing
`Multiple versions of Lit loaded. Loading multiple versions is not
recommended.` — coming from `@chatwoot/ninja-keys` and
`@material/mwc-icon` each pulling their own copy of Lit through Vite's
pre-bundling.

`_KONVERSIO/HANDOFF.md` lesson 10 explicitly listed this as upstream
noise to ignore. We ignored that rule.

The "fix" went through three escalating versions:

1. **`resolve.dedupe: ['lit']` + `optimizeDeps.include: [...]` in
   `vite.config.ts`.** Worked in dev. Crashed esbuild pre-bundling
   because `@material/mwc-icon/mwc-icon-host.css.js` does
   `import { css } from 'lit'` and esbuild can't resolve that bare
   specifier from inside the pnpm-isolated `.css.js` sub-file.

2. **`pnpm patch @material/mwc-icon@0.25.3`** rewriting the two bare
   `from 'lit'` imports to `from 'lit/index.js'`. The patch is real,
   committed, with metadata in `package.json` `pnpm.patchedDependencies`.
   Worked in dev. But it broke the production Rollup build, because
   `lit`'s own `package.json` has a restrictive `exports` field that
   does NOT expose the `./index.js` subpath. Rollup follows `exports`
   strictly; esbuild's pre-bundler is more forgiving. So the fix passed
   dev validation and would have broken Heroku deploys.

3. **Removing `dedupe`, keeping `optimizeDeps`, hoping for the best.**
   Got a *different* failure on the prod build:
   `Missing "./index.js" specifier in "lit" package`. Same root cause —
   the patched mwc-icon was still inside pnpm's `.pnpm_patches/` staging
   directory even after the patch entry was removed from `package.json`.
   pnpm's store doesn't garbage-collect aggressively.

While trying to verify any of the above, three parallel infrastructure
issues piled on:

- **Vite container was simply not running.** We hadn't noticed because
  Rails was happily serving the last-built chunks from `public/vite-dev/`
  (the May 17 21:59 build, which predated the notifications fix). The
  feature couldn't possibly work because the JS containing the hook
  wasn't in the served bundle. Took us 90+ minutes to look at
  `docker compose ps`.

- **After starting Vite, every asset returned 403.** Vite 5 ships with
  `server.allowedHosts` default-deny; the Docker compose proxy hits Vite
  with `Host: vite` (the service name) which isn't on the allowlist.
  Easy 3-line fix; took 20 minutes to recognize.

- **Full rebuild kept failing — first with a real Lit error, then with
  ENOMEM, then with the `lit/index.js` exports failure** from the
  lingering patch. Each fix exposed the next layer.

---

## Why this kept escalating

Three forces compounded:

1. **The handoff rule existed for exactly this reason and we ignored
   it.** Lesson 10 said don't chase the Lit warning. We chased it
   anyway when the user asked, then doubled down twice ("FIX", "GO DO IT
   THEN") instead of de-escalating after the first failure.

2. **Dev-mode fixes look like full fixes.** `optimizeDeps` only affects
   Vite's dev pre-bundler. The production Rollup build is a separate
   pipeline with different resolution rules. "It works in `docker
   compose restart vite`" is not the same as "the deploy will succeed."
   The `CLAUDE.md` already documents this — *"Local pre-deploy check:
   `bundle exec rails assets:precompile`. Run this before every
   `git push heroku main`"*. We skipped that step on every iteration.

3. **We mistook infrastructure failure for fix failure.** When the
   favicon didn't flip, we kept changing the favicon helper code. The
   real issue was the bundle in the browser didn't contain *any* of our
   recent JS commits — Vite container had been down for hours.
   Diagnostic discipline (look at the served file content, look at
   container status) would have caught this much earlier.

---

## Rules we're adopting

These supersede or refine existing handoff lessons.

### 1. The handoff's "ignore this" list is load-bearing. Don't override it without process.

Lesson 10 items are there because somebody already spent the hours.
Before chasing one of them, write down (a) what the actual user-visible
cost is, (b) why this session is different, (c) the rollback plan if
the fix breaks something else. If you can't fill those in, leave it
alone.

In hindsight: the "Multiple versions of Lit loaded" warning has zero
user impact. The fix cost was multi-hour. The cost/benefit was never
favorable.

### 2. Every Vite config change must pass `bin/vite build` before commit.

`docker compose restart vite` is necessary but not sufficient. Run the
production build inside the container — same one Heroku runs at
release:

```
docker compose exec -e NODE_OPTIONS=--max-old-space-size=4096 \
  vite bin/vite build
```

If this fails, the change does NOT ship. No exceptions. The dev server
and the production builder are two different code paths and they don't
agree on package resolution.

### 3. Before debugging a frontend hook that "doesn't fire", verify the hook is in the bundle.

```js
// in DevTools console
await fetch('/vite-dev/.vite/manifest.json')
  .then(r => r.json())
  .then(m => fetch('/vite-dev/' + m['app/javascript/entrypoints/dashboard.js'].file))
  .then(r => r.text())
  .then(t => t.includes('YOUR_NEW_FUNCTION_NAME'))
```

`true` → the bundle has your code; bug is elsewhere. `false` → rebuild
before changing anything else. This 30-second check would have saved
us hours.

### 4. `docker compose ps` is the first command when anything weird happens.

Sounds dumb. Reality: we burned 90+ minutes assuming Vite was up because
it had been earlier in the session. Make this check muscle memory.

### 5. pnpm patches are a real fork. Treat them that way.

A `pnpm patch` survives `pnpm install` and travels with the lockfile —
but the staged files at `node_modules/.pnpm_patches/` and the
`_patch_hash=...` directory in `.pnpm/` are sticky. Removing a patch
from `package.json` is **not** enough to fully unwind it. To cleanly
remove:

```
# Remove the patch entry from package.json (the `pnpm.patchedDependencies` block)
# Remove the patch file from patches/
rm -rf node_modules/.pnpm_patches
pnpm install
```

And only believe it's gone after `grep -rln '<patched-import>'
node_modules/.pnpm/` comes back empty.

### 6. "Works in dev" is not "ships".

Already in CLAUDE.md, restating because we violated it:
> Run `bundle exec rails assets:precompile` locally before every `git
> push heroku main`.

We never ran this for either Lit-related commit. Both would have
failed CI/deploy. Catch it locally where the cost is a minute, not in
Heroku's 5-minute release cycle.

---

## What's actually being shipped from this session

After the planned cleanup (revert `f7739dbb1` and `76a19633a`):

| Commit | Purpose | Status |
|---|---|---|
| `2d7efa65b` | favicon + audio on `assignee.changed` for the current user | **Kept** — the actual feature |
| `db1010c88` | pilot-utilities: route briefing/summary to correct draft + spinner | Kept |
| `c5dcd06d5` | message.id accepts Number\|String for optimistic-send tokens | Kept |
| `1ff824b88` | regenerate favicons from new masters (Pillow LANCZOS) | Kept |
| `f7739dbb1` | Lit dedupe + mwc-icon patch + optimizeDeps | **Reverted** — broke prod build |
| `76a19633a` | docs: mark Lit warning fixed, add lesson 11 | **Reverted** — describes the broken fix |

Plus one new small commit worth keeping: `server.allowedHosts: ['vite',
'localhost']` in `vite.config.ts` — a legitimate Vite 5 fix unrelated
to the Lit detour, so it survives as its own commit.

---

## Open questions for follow-up sessions

1. **Why does `assignee.changed` fire twice for a single bot handoff?**
   We captured two events 325ms apart, both with the same `assignee_id`.
   Probably the Autopilot service races with Chatwoot's standard
   auto-assignment policy. Idempotent on the favicon side but worth
   identifying the duplicate dispatcher path.

2. **Is the Vite container's crash silent enough to deserve a health
   check?** It died at some point earlier in the session without an
   obvious symptom — Rails kept serving stale chunks. A
   `docker compose ps` heartbeat printed by the dev startup script would
   surface this.

3. **Is HMR actually doing anything in this setup?** With
   `autoBuild: false`, Rails serves manifest paths but the JS bytes are
   proxied to Vite (or fall back to `public/vite-dev/` if Vite is
   down). The dev-loop audit agent claims `@vite/client` injection
   handles HMR module-push, but observation suggests Rails is serving
   content-hashed build artifacts, not live source. Worth a 30-minute
   investigation when we're not under pressure to ship something.
