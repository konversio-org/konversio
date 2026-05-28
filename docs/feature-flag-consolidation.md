# Feature Flag Consolidation Plan

## Issue: Two Feature Flag Systems in One Codebase

Konversio currently has **two parallel feature flag mechanisms** for the same type of thing (account-level boolean toggles):

| | System A: Featurable | System B: Pilot Columns |
|---|---|---|
| **Origin** | Chatwoot (inherited) | Konversio (independent implementation) |
| **Storage** | `feature_flags` bigint bitfield | 13 `pilot_*_enabled` boolean columns |
| **Definition** | `config/features.yml` (58 entries) | Migration files only |
| **Admin UI** | Super Admin checkbox grid | None (DB-only) |
| **API** | `account.enabled_features` hash | 13 explicit `json.pilot_*_enabled` lines |
| **Frontend** | `account.features.feature_name` | `account.pilot_briefing_enabled` |

Existing Pilot entries already in Featurable: `pilot_integration`, `pilot_integration_v2`, `pilot_tasks`. No collision with the column names.

### The 13 Pilot Columns

| Column | Used? | Gated by |
|--------|-------|----------|
| `pilot_enabled` | Master switch | BaseService + all controllers |
| `pilot_briefing_enabled` | Active | BriefingService, BriefingsController, useBriefing.js |
| `pilot_copilot_enabled` | Active | CopilotService, CopilotMessagesController, usePilot.js |
| `pilot_autopilot_enabled` | Active | AutopilotService, ResponsesController, AutopilotInferenceJob |
| `pilot_logbook_enabled` | Active | LogbookEntriesController, BaseService#logbook_context_for |
| `pilot_summary_enabled` | Active | SummaryService, SummariesController, useSummary.js |
| `pilot_csat_analysis_enabled` | Active | CsatAnalysisJob, CsatSurveyResponse model |
| `pilot_follow_up_enabled` | Active | FollowUpService, FollowUpsController, useFollowUp.js |
| `pilot_rewrite_enabled` | Active | RewriteService, RewritesController, useRewrite.js |
| `pilot_label_suggestion_enabled` | Active | LabelSuggestionJob, PilotAutopilotListener |
| `pilot_tools_enabled` | Unused | — |
| `pilot_autoresolve_enabled` | Unused | — |

---

## Observations

1. **The boolean columns were likely a path-of-least-resistance choice** during the Pilot rewrite, not a deliberate architectural decision. Boolean columns are simpler to write than wrangling `flag_shih_tzu`, but create ongoing divergence cost.

2. **Two systems = two places to debug, two places to add flags, two mental models** for contributors. Someone familiar with Chatwoot expects `config/features.yml` — they won't find Pilot flags there.

3. **No admin UI for Pilot flags.** The Super Admin checkbox grid works for Featurable flags. Pilot flags can only be toggled via SQL.

4. **The benefits of dedicated columns are small and post-hoc**: partial indexes (replicable), readable psql (minor), no-bitfield-ordering-constraint (rarely relevant).

5. **The JSONB `settings.pilot_features`** (managed via `PilotFeaturable` concern + `PreferencesController`) is a third system, but it's configuration (model/feature preferences), not feature-gating. It stays.

6. **`pilot_tools_enabled` and `pilot_autoresolve_enabled`** exist in the schema but no code checks them. They're reserved for future use.

---

## Options

### Option A: Full Migration into Featurable (Recommended)

Merge Pilot flags into `features.yml` + bitfield, drop boolean columns.

- Add 13 entries to `config/features.yml`
- Data migration: copy boolean values → bitfield bits
- Rewrite `BaseService#feature_enabled?` to delegate to Featurable
- Rewrite 8 controllers, 5+ jobs/listeners
- Rewrite 6 frontend composables, 5 Vue components
- Remove 13 explicit lines from `_account.json.jbuilder` (the existing `json.features` line picks them up automatically)
- Separate post-deploy migration: drop the 13 columns + partial index

**Cost:** ~40 files touched, data migration touches every account row.
**Benefit:** Single system, Super Admin UI works for Pilot, new contributors have one mental model, aligns with Chatwoot.

### Option B: Shadow Entries in features.yml (No Schema Change)

Add Pilot entries to `features.yml` so admins see them in the checkbox grid, but keep the boolean columns. Make Featurable delegate to the boolean columns for those specific names.

**Cost:** Glue code in Featurable concern (delegate `feature_pilot_briefing` to the boolean column).
**Benefit:** Admin UX win without touching the schema or production data.

### Option C: Do Nothing

Leave both systems as-is.

**Cost:** Ongoing divergence maintenance tax, no admin UI for Pilot.
**Benefit:** Zero migration risk, zero code changes.

---

## Implementation Plan (Option A)

### Phase 1: Add Pilot Entries to `config/features.yml`

Append 13 entries at the end of `config/features.yml` (appending preserves existing bit positions — the file header says "DO NOT change the order of features EVER"):

```yaml
- name: pilot_enabled
  display_name: Pilot
  enabled: true
- name: pilot_briefing
  display_name: Pilot Briefing
  enabled: true
- name: pilot_copilot
  display_name: Pilot Copilot
  enabled: true
- name: pilot_autopilot
  display_name: Pilot Autopilot
  enabled: true
- name: pilot_logbook
  display_name: Pilot Logbook
  enabled: true
- name: pilot_tools
  display_name: Pilot Tools
  enabled: true
- name: pilot_autoresolve
  display_name: Pilot Autoresolve
  enabled: true
- name: pilot_summary
  display_name: Pilot Summary
  enabled: true
- name: pilot_csat_analysis
  display_name: Pilot CSAT Analysis
  enabled: true
- name: pilot_follow_up
  display_name: Pilot Follow Up
  enabled: true
- name: pilot_rewrite
  display_name: Pilot Rewrite
  enabled: true
- name: pilot_label_suggestion
  display_name: Pilot Label Suggestion
  enabled: true
```

### Phase 2: Data Migration (Copy Booleans → Bitfield)

Create a reversible migration that:
1. For each `pilot_*_enabled` column, reads the boolean value
2. Calls `account.enable_features('pilot_*')` or `account.disable_features('pilot_*')` to set the corresponding bitfield bit
3. Runs within a transaction

### Phase 3: Rewrite Backend Flag Checks

**`Custom::Pilot::BaseService#feature_enabled?`** — change from:
```ruby
column = "pilot_#{feature}_enabled"
account.pilot_enabled && account.public_send(column)
```
to:
```ruby
account.feature_enabled?('pilot_enabled') && account.feature_enabled?("pilot_#{feature}")
```

**Controllers** (8 files, e.g. `briefings_controller.rb:27`): change from:
```ruby
return if Current.account.pilot_enabled && Current.account.pilot_briefing_enabled
```
to:
```ruby
return if Current.account.feature_enabled?('pilot_enabled') && Current.account.feature_enabled?('pilot_briefing')
```

**Jobs / Listeners** (5+ locations): same pattern.

**Account JSON builder** (`_account.json.jbuilder`): remove lines 32-43 (the 13 individual `json.pilot_*_enabled` lines). The existing `json.features @account.enabled_features` on line 21 will now include Pilot flags automatically.

### Phase 4: Rewrite Frontend

**Composables** (6 files: `usePilot.js`, `useBriefing.js`, `useSummary.js`, `useRewrite.js`, `useFollowUp.js`): change from:
```js
return Boolean(account.pilot_enabled && account.pilot_briefing_enabled);
```
to:
```js
const features = account.features || {};
return Boolean(features.pilot_enabled && features.pilot_briefing);
```

**Vue components** (5 files: `PilotActionsMenu.vue`, `SummarizeButton.vue`, `SuggestedLabelChips.vue`, `FollowUpSuggestionsButton.vue`, `BriefingButton.vue`): same pattern — read from `account.features` instead of top-level `account.pilot_*_enabled`.

**`featureFlags.js`**: add constants for the new flags.

### Phase 5 (Post-Deploy, Separate Migration): Drop Boolean Columns

After the deploy is confirmed stable, a separate migration drops:
- 13 `pilot_*_enabled` columns from `accounts`
- The partial index `index_accounts_on_pilot_enabled`

### Out of Scope (Unchanged)

- `PilotFeaturable` concern — JSONB preferences, different system
- `PreferencesController` — model/feature config, not feature gates
- `config/llm.yml` — model definitions
- `lib/pilot/base_task_service.rb` — already uses Featurable via `account.feature_enabled?('pilot_tasks')`

### Files Touched

**Backend (~18 files):**
- `config/features.yml`
- `db/migrate/` (2 migrations: data copy + column drop)
- `custom/app/services/custom/pilot/base_service.rb`
- 8 Pilot controllers
- 5+ jobs/listeners
- `app/views/api/v1/models/_account.json.jbuilder`
- `app/models/account.rb` (schema annotation)
- `db/schema.rb`

**Frontend (~13 files):**
- 6 composables
- 5 Vue components
- `app/javascript/dashboard/featureFlags.js`
- `app/javascript/dashboard/store/modules/accounts.js` (may need no change — the getter already reads from `features` hash)

**Specs (~20+ files):** Update any spec that sets/checks `pilot_*_enabled` columns.

### End State

Single system, single mental model, Super Admin UI works for Pilot toggles for free, `config/features.yml` is the single source of truth for all feature flags.
