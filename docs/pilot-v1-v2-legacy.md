# Pilot v1 vs v2: where the legacy flags came from and what to do with them

After the Captain → Pilot rename, three flag names in `config/features.yml`
look like they could still be doing meaningful work:

- `pilot_integration` (was `captain_integration` upstream)
- `pilot_integration_v2` (was `captain_integration_v2` upstream)
- `pilot` (the new Konversio master switch — unrelated lineage)

This document explains what each one means today, the upstream history
that produced them, and what cleanup options exist.

## The story

Chatwoot's "Captain" AI feature went through two architectural generations:

- **Captain v1** — original integration, gated by `captain_integration`.
- **Captain v2** — introduced in upstream PR
  [#11920 "New Assistants Edit Page"](https://github.com/chatwoot/chatwoot/pull/11920),
  gated by `captain_integration_v2`. Brought the Assistants editing UI
  plus internal architectural changes.

Two flags so Chatwoot's SaaS could route accounts between v1 and v2
independently — a standard parallel-rollout pattern.

There's also `captain_v1_action_classifier`, a sub-flag controlling
v1's action-routing classifier. Mostly retired.

## Where Chatwoot stands today (upstream/develop)

`captain_integration` (v1) is now a **dead flag definition**: still
declared in `config/features.yml` but no application code reads it.
Chatwoot has retired v1 from the runtime but kept the flag entry for
historic accounts.

`captain_integration_v2` is still actively gating four code paths in
`enterprise/`:

| File | What v2 changes |
|---|---|
| `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb` | `captain_v2_enabled?` private predicate — alters assistant request handling |
| `enterprise/app/helpers/captain/chat_response_helper.rb` | `captain_v1_assistant?` returns true *only when v2 is OFF* — legacy assistant pathway |
| `enterprise/app/controllers/api/v1/accounts/captain/custom_tools_controller.rb` | Custom tools become natively accessible when v2 is on (no separate `custom_tools` flag needed) |
| `enterprise/app/jobs/captain/conversation/response_builder_job.rb` | Different response/handoff handling (v1 had a `report_v1_handoff_not_executed` error tracker for a known reliability bug) |

So upstream the divergence is real: v1 and v2 are two parallel
implementations of assistants + tools + handoff, switchable per account.
Most Chatwoot SaaS customers are presumably on v2 by now; v1 stays
alive for the long tail.

## Where Konversio stands today (main)

Per [`FORK_STRATEGY.md`](../FORK_STRATEGY.md), Konversio's Pilot is a
**clean-room rebuild from a behavioral spec**, not a port of either
Chatwoot version. The new architecture happens to be v2-shaped
(Assistants, Documents, Scenarios, Custom Tools, handoff via
`HandoverEvaluator::HANDOVER_SENTINEL`) because v2 is where the
architecture had landed conceptually — but the actual code is new.

There is **no v1 vs v2 split inside Konversio**. One Pilot
implementation, gated by the new master `pilot` flag plus 12 sub-flags
(`pilot_briefing`, `pilot_copilot`, `pilot_autopilot`, `pilot_logbook`,
etc.). Verified:

```
$ grep -rn "pilot_v2_enabled\|pilot_v1_assistant" app/ lib/ custom/
(no matches)
```

The two legacy flags' status in Konversio:

| Flag | Status in Konversio code | Consumers |
|---|---|---|
| `pilot_integration` (was v1) | Alive but only gates Chatwoot-inherited UI bits that survived the rename | 6 callers: `featureFlags.js`, `SidepanelSwitch.vue`, `CopilotContainer.vue`, `account/Index.vue`, `inbox_csat_templates_controller.rb` |
| `pilot_integration_v2` (was v2) | **Completely dead** — defined as a constant in `featureFlags.js:41`, never checked anywhere | None functionally |
| `pilot` (new master) | The actual switch for the rebuilt Pilot suite | All 12 Pilot sub-flags + all `Custom::Pilot::*` services + all Pilot frontend composables |

`pilot_integration` is *not* a v1-architecture gate in Konversio. It
exists today as a "is the Chatwoot legacy Copilot/Pilot UI surfaced for
this account" toggle. The UI surfaces it controls (Copilot drawer
sidepanel, account-settings Pilot block, CSAT inbox template special
case) all predate Konversio's clean-room Pilot work and survived the
rename mechanically.

## Options

### Option A — minimal cleanup (recommended for "just stop the confusion")

- Delete `pilot_integration_v2` entry from `config/features.yml`.
- Delete `FEATURE_FLAGS.PILOT_V2` constant from
  `app/javascript/dashboard/featureFlags.js`.
- Leave `pilot_integration` alone.

Zero risk, ~5-minute change. Removes the dead constant that has no
consumers and the flag entry that admins would otherwise puzzle over.
Does not change any runtime behavior.

### Option B — minimal cleanup + clarity rename (recommended for medium-term hygiene)

Everything in A, plus:

- Rename `pilot_integration` → `chatwoot_legacy_copilot_ui` (or similar
  descriptive name) in `config/features.yml`, `featureFlags.js`, and
  the 6 caller files. Add a one-line `display_name` and code comment
  explaining it gates inherited Chatwoot UI bits, not the Pilot AI
  itself.

~30-minute change. New contributors stop confusing it with the new
`pilot` master flag. Runtime behavior unchanged.

### Option C — full retirement (recommended for "do it properly")

Everything in A, plus an audit of the 6 `pilot_integration` callers.
For each surface, decide:

1. **Keep the UI, migrate to the new master.** Change the check from
   `FEATURE_FLAGS.PILOT` (`'pilot_integration'`) to a check against the
   new `pilot` flag (e.g. via the existing `Featurable#feature_enabled?`).
2. **Remove the UI entirely.** Konversio's Pilot already has its own
   Copilot drawer, account settings block, and AI surfaces. Some of
   the Chatwoot-inherited bits may now be redundant or actively
   conflicting with the new design.

Once all six callers are migrated or removed, delete `pilot_integration`
from `config/features.yml` and `featureFlags.js`.

Higher effort (~2–4 hours), and requires UX judgment per surface
(keep vs. remove). Yields a codebase with a single Pilot flag concept.

## Recommendation

Start with **Option A right now** — it costs nothing and immediately
removes a dead constant + misleading flag entry. Defer the rename or
retirement decision (B or C) until Pilot's UI surfaces have stabilised
enough to be reviewed against the Chatwoot-inherited legacy bits.
