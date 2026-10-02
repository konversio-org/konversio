# Parity resume brief — Phase 3 waves 2–3

Handoff doc for continuing the Chatwoot-parity port in a fresh opencode session.
Read this top-to-bottom, then execute the per-wave recipe.

## Mission

Bring Konversio (hard fork of Chatwoot v4.13.0) to parity with upstream v4.18.0
for the remaining **clean-room `pilot-*`** changes. The spec set already exists;
you are implementing from it. Parent tracker: `openspec/changes/_parity-coverage-v4.14-to-v4.18.md`.

## Repo rules (non-negotiable)

- Repo: `/Users/rcoenen/Dev/Konversio-Org/konversio-github` (worktrees under `/Users/rcoenen/Dev/Konversio-Org/tmp/`).
- Hard fork, **no upstream tracking**; 100% MIT; self-hosted only; `enterprise/` removed; Captain → `Pilot::`.
- **CLEAN-ROOM:** these `pilot-*` changes originate from upstream's EE/Captain code. The specs already
  state requirements in original wording. Implement from the spec + existing `Pilot::` code only.
  **Do NOT read `/tmp/chatwoot-upstream/enterprise/`** or copy upstream prompts/labels/regex/naming.
- MIT code (non-EE) may be ported verbatim; adapt for `Pilot::`/Konversio branding.
- Commit style: Conventional Commits; never commit secrets; tick tasks.md `[ ]`→`[x]`.

## Current state (as of handoff)

- `main` @ `9ef16e537` — pushed to `origin`.
- Checkpoints (all pushed): `phase-0` @ `90673ffee`, `phase-1` @ `e569c87c7`,
  `phase-2` @ `907afefe6`, `phase-3a` @ `9ef16e537`.
  To undo/restore a phase: `git reset --hard phase-N` (or check out the branch).
- Merged & verified already: Phase 0 (realtimekit, platform-maintenance, channel-security);
  Phase 1 (reporting-drilldowns, inbox-conversation-ux, search-and-tables, composer-productivity,
  help-center-revamp, help-center-rich-content); Phase 2 (whatsapp-platform, voice-calling,
  data-imports, assignment-and-automation, companies-management, super-admin-governance,
  onboarding-and-setup, audit-log-governance); Phase 3 wave 1 (pilot-conversation-outcomes,
  pilot-agent-sessions-and-citations, pilot-knowledge-auto-sync, pilot-reply-suggestion,
  pilot-playground).

## Remaining work

**Wave 2** (all clean-room; branch off current `main`):
- `pilot-response-integrity` — needs the `lib/pilot/structured_reply.rb` contract now on `main` (from wave 1).
- `pilot-audiences-and-lifecycle`
- `pilot-faq-suggestions`

**Wave 3** (branch off post-wave-2 `main`):
- `pilot-assistant-analytics` — hard dependency on `pilot-conversation-outcomes` (already merged).
  Also honour `reporting-drilldowns` task 16: the reopen-rate requirement
  (`pilot-assistant-reopen-rate-performance`: reuse resolved-conversation total as denominator,
  skip the reopen query at zero resolutions, split range-dependent vs range-independent endpoints).

## Environment / gotchas (learned the hard way)

- Host mode. `.env.development.local` (localhost overrides) + `.env.test.local` (isolated test DB)
  must be copied/written into each worktree. `db:create db:test:prepare` builds the test DB from `db/schema.rb`.
- **NEVER run `db:migrate` from scratch and NEVER `db:schema:dump`** — the 2023 migration
  `20231211010807_add_cached_labels_list.rb` fails (`ActsAsTaggableOn::Taggable::Cache`) and a dump
  clobbers the merged `schema.rb`. Resolve `db/schema.rb` conflicts by hand: keep the auto-merged body
  and set the `define(version: ...)` line to the **max migration timestamp** in `db/migrate/`.
- **Duplicate migration versions**: parallel agents sometimes pick the same timestamp. Detect
  `ls db/migrate | grep -oE '^[0-9]+' | sort | uniq -d` and `git mv` one to an unused later timestamp
  (keep the class name; `20261003000002` was already renumbered to `...000003`).
- `git config rerere.enabled true` is set — repeated `schema.rb` version conflicts auto-resolve.
- Pre-commit husky hook runs lint-staged (eslint/rubocop) and **fails the commit** on errors
  (e.g. duplicate `const` declarations from a bad auto-merge). Fix, `git add`, re-commit.
- Isolated DB + Redis per worktree to allow parallel agents. Redis indexes are 0–15:
  main=0; wave-1 used 6–10; **free for wave 2: 11,12,13; wave 3: 14**.
  DB name convention: `chatwoot_test_<slug>`.
- OrbStack/Docker can crash under many concurrent rspec/vitest runs. If Postgres refuses connections:
  `cd /Users/rcoenen/Dev/Konversio-Org/konversio-github && docker compose up -d postgres redis`, then wait ~8s.

## Per-wave recipe

1. **Create worktrees + env** (from repo root). Replace `WT`/`SLUG`/`BR`/`REDIS`/`DB`:
   ```bash
   cd /Users/rcoenen/Dev/Konversio-Org/konversio-github
   git worktree add /Users/rcoenen/Dev/Konversio-Org/tmp/WT -b BR main
   cp /Users/rcoenen/Dev/Konversio-Org/konversio-github/.env.development.local /Users/rcoenen/Dev/Konversio-Org/tmp/WT/.env.development.local
   printf 'POSTGRES_HOST=localhost\nPOSTGRES_PORT=5432\nREDIS_URL=redis://localhost:6379/REDIS\nPOSTGRES_DATABASE=DB\n' > /Users/rcoenen/Dev/Konversio-Org/tmp/WT/.env.test.local
   ```
2. **Bootstrap** each: `( cd tmp/WT && pnpm install --frozen-lockfile && RAILS_ENV=test bundle exec rails db:create db:test:prepare )` (parallel OK).
3. **Launch agents in parallel** (one `task` call per change, `subagent_type: general`). Agent prompt must include:
   - Worktree path + branch; never touch the main checkout; don't push/merge.
   - CLEAN-ROOM rule (above) + read the 4 change docs in `openspec/changes/<change>/`.
   - Environment: run every command with the worktree as CWD (`workdir` param); isolated DB/redis;
     `RAILS_ENV=test bundle exec rspec`; `RAILS_ENV=test bundle exec rails db:migrate` if adding migrations
     (then re-run specs); full `pnpm test` if frontend touched.
   - Verify: port/author the §Validation specs green; `bundle exec rubocop -a` on touched Ruby; `pnpm eslint`.
   - Commit incrementally on its branch; tick tasks.md.
   - **Write the full report to `openspec/changes/<change>/IMPLEMENTATION.md` and return only a ≤8-line summary**
     (files count, test results, commits, blockers). This is what keeps the coordinator cheap.
4. **Merge** each branch into `main` (`git merge --no-ff feat/<change> -m "merge: <change> into main"`),
   one at a time. Resolve conflicts as unions; for heavy/overlapping conflicts delegate to a focused
   subagent that returns a terse report. Watch for duplicate migration versions (step above) and the
   pre-commit hook. Commit each merge only after `git diff --name-only --diff-filter=U` is empty.
5. **Verify on merged `main`**:
   ```bash
   RAILS_ENV=test bundle exec rails db:test:prepare   # rebuild test DB from schema.rb
   git diff --name-only 9ef16e537..HEAD -- '*.rb'    # rubocop on these (exclude db/schema.rb)
   git diff --name-only 9ef16e537..HEAD -- '*.js' '*.vue'  # eslint on these
   bundle exec rspec $(changed *_spec.rb)            # rspec on changed specs
   pnpm test                                          # full vitest
   ```
   All green before checkpointing.
6. **Checkpoint + push**: update `_parity-coverage-v4.14-to-v4.18.md` (mark the wave's rows `merged to main`
   and add a short wave section with commits + verification + deferrals; force-add since `openspec/` is
   gitignored: `git add -f openspec/...`), commit, then:
   ```bash
   git branch phase-3b && git push origin main phase-3b     # then phase-3c for wave 3
   ```

## Definition of done

- All nine `pilot-*` change dirs merged to `main` and verified; checkpoints `phase-3b` and `phase-3c` pushed.
- `_parity-coverage-v4.14-to-v4.18.md` shows every implemented change as `merged to main`, with deferrals recorded.
- Full rubocop + eslint + rspec + `pnpm test` green on the final `main`.

## Known deferrals to carry forward (not blockers)

- Manual/browser/credentialed smoke tests across all changes (no live LLM provider / Meta WABA / browser).
- `pilot-conversation-outcomes`: quota-handoff sub-path (no quota enforcement exists).
- `pilot-knowledge-auto-sync`: citation eligibility hook depends on agent-sessions resolver (now merged — verify).

## Handing to Kimi Code (K3)

Everything here is tool-agnostic (plain `git`/shell), so Kimi Code can execute it directly.

**Before you start**
- `git fetch origin`; branch every worktree off `origin/main` (`b244a2f77` or later) — NOT the `phase-*` branches.
- Run **one tool at a time** on this repo — do not run Kimi Code and opencode simultaneously on the same worktrees.
- The Phase-3 wave-1 worktrees/branches (`wt-outcomes`, `wt-sessions`, `wt-knowledge`, `wt-reply`, `wt-playground`)
  are already merged — leave them; do not reuse.

**Allocation for the remaining waves**

| Wave | Change | Worktree | Branch | Test DB | Redis |
|---|---|---|---|---|---|
| 2 | pilot-response-integrity | tmp/wt-integrity | feat/pilot-response-integrity | chatwoot_test_integrity | 11 |
| 2 | pilot-audiences-and-lifecycle | tmp/wt-audiences | feat/pilot-audiences-and-lifecycle | chatwoot_test_audiences | 12 |
| 2 | pilot-faq-suggestions | tmp/wt-faq | feat/pilot-faq-suggestions | chatwoot_test_faq | 13 |
| 3 | pilot-assistant-analytics | tmp/wt-analytics | feat/pilot-assistant-analytics | chatwoot_test_analytics | 14 |

**Swarm invocation**
- Wave 2: one agent per change, all 3 in parallel. Wave 3: a single agent.
- Each agent prompt MUST contain: its worktree path + branch; "never modify the main checkout; do not push or merge";
  the **clean-room** rule (above); the 4 spec docs to read; the environment block (isolated DB/Redis, run every command
  with the worktree as CWD, `RAILS_ENV=test bundle exec rspec`, `db:migrate` if adding migrations, full `pnpm test` if
  frontend touched); verify (rubocop/eslint + §Validation specs green); commit incrementally + tick tasks.md.
- **Context-frugal reporting:** each agent must write its full report to `openspec/changes/<change>/IMPLEMENTATION.md`
  and return only a ≤8-line summary.

**After each wave**
- Merge each branch into `main` one at a time; resolve conflicts as unions; dedupe migration versions
  (`ls db/migrate | grep -oE '^[0-9]+' | sort | uniq -d`); let the husky hook run.
- Rebuild + verify on `main` (recipe step 5), update the tracker (force-add), then
  `git branch phase-3b && git push origin main phase-3b` (then `phase-3c` after wave 3).

**Quota fallback**
- If you hit `403 … 5-hour usage limit`, stop at the last good checkpoint — nothing is lost. `main` and the
  `phase-*` branches are on `origin`; any tool (including opencode) can resume from this brief.
