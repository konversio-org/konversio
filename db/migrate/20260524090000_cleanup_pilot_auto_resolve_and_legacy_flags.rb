# frozen_string_literal: true

# Repair migration for environments where the legacy Pilot flag drop was marked
# as run while the columns remained on accounts. Also removes the dead
# auto-resolve "evaluated" mode now that the evaluator has been removed.
class CleanupPilotAutoResolveAndLegacyFlags < ActiveRecord::Migration[7.1]
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
    remove_index :accounts, name: 'index_accounts_on_pilot_enabled' if index_exists?(:accounts, :id, name: 'index_accounts_on_pilot_enabled')
    remove_column :accounts, :legacy_feature_flags if column_exists?(:accounts, :legacy_feature_flags)

    PILOT_BOOLEAN_COLUMNS.each do |column|
      remove_column :accounts, column if column_exists?(:accounts, column)
    end

    execute <<~SQL.squish
      UPDATE accounts
      SET settings = jsonb_set(settings, '{pilot_auto_resolve_mode}', '"legacy"'::jsonb, true)
      WHERE settings->>'pilot_auto_resolve_mode' = 'evaluated'
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Legacy Pilot flag columns and evaluated auto-resolve mode are intentionally removed.'
  end
end
