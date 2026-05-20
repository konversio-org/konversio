# frozen_string_literal: true

# Phase 2 of the unify-feature-flags openspec change. Drops the legacy
# bitfield and the 12 dedicated Pilot boolean columns, leaving the single
# `accounts.feature_flags` JSONB column as the source of truth.
#
# Safe to run because:
#   * `Featurable`'s dynamic methods (`account.pilot_briefing_enabled`,
#     `account.feature_pilot_briefing?`, etc.) already read from JSONB
#   * Phase 1 backfilled JSONB to match the boolean columns
#   * No code in app/ lib/ custom/ reads `legacy_feature_flags`
#
# This migration is intentionally one-way. Reconstructing the dropped
# columns would require a fresh data migration reading from JSONB and
# rewriting bitfield bits, which is a deliberate operation rather than
# something `rails db:rollback` should silently do.
class DropLegacyFeatureFlagColumns < ActiveRecord::Migration[7.1]
  PILOT_BOOLEAN_COLUMNS = %i[
    pilot_enabled
    pilot_briefing_enabled
    pilot_copilot_enabled
    pilot_autopilot_enabled
    pilot_logbook_enabled
    pilot_tools_enabled
    pilot_autoresolve_enabled
    pilot_summary_enabled
    pilot_csat_analysis_enabled
    pilot_follow_up_enabled
    pilot_rewrite_enabled
    pilot_label_suggestion_enabled
  ].freeze

  def up
    # Drop the partial index that depends on pilot_enabled before the column.
    if index_exists?(:accounts, :pilot_enabled, name: 'index_accounts_on_pilot_enabled')
      remove_index :accounts, name: 'index_accounts_on_pilot_enabled'
    end

    remove_column :accounts, :legacy_feature_flags

    PILOT_BOOLEAN_COLUMNS.each do |col|
      remove_column :accounts, col
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Phase 2 is one-way. Rebuilding the dropped columns requires an ' \
          'explicit data migration that reads from feature_flags JSONB. ' \
          'See docs/feature-flag-consolidation.md.'
  end
end
