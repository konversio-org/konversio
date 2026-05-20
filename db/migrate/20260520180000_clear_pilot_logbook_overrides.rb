# frozen_string_literal: true

# Strips the explicit `pilot_logbook` override from every account's
# feature_flags JSONB so accounts fall through to the new YAML default
# (`enabled: false`, see config/features.yml) while the feature is in
# development.
#
# Why a separate migration instead of just flipping the YAML?
# Phase 1's backfill wrote an explicit `pilot_logbook: true` into every
# existing account's feature_flags. With explicit overrides in place, a
# YAML default change has no effect — Featurable's lookup returns the
# override first. Removing the key here lets the new YAML default win.
#
# When the feature is ready to ship to everyone, the recovery path is:
#   1. Flip config/features.yml back to `enabled: true`
#   2. No data migration needed — accounts with no override get the
#      new default automatically.
class ClearPilotLogbookOverrides < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      UPDATE accounts
      SET feature_flags = feature_flags - 'pilot_logbook'
      WHERE feature_flags ? 'pilot_logbook'
    SQL
  end

  def down
    # Restore the override to true (its Phase 1 backfilled value), so a
    # rollback returns accounts to the state they were in immediately
    # after Phase 1.
    execute <<~SQL.squish
      UPDATE accounts
      SET feature_flags = feature_flags || jsonb_build_object('pilot_logbook', true)
      WHERE NOT (feature_flags ? 'pilot_logbook')
    SQL
  end
end
