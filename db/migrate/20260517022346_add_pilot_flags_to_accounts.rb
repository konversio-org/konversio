class AddPilotFlagsToAccounts < ActiveRecord::Migration[7.1]
  def change
    change_table :accounts, bulk: true do |t|
      t.boolean :pilot_enabled, default: false, null: false
      t.boolean :pilot_briefing_enabled, default: false, null: false
      t.boolean :pilot_copilot_enabled, default: false, null: false
      t.boolean :pilot_autopilot_enabled, default: false, null: false
      t.boolean :pilot_logbook_enabled, default: false, null: false
      t.boolean :pilot_tools_enabled, default: false, null: false
      t.boolean :pilot_autoresolve_enabled, default: false, null: false
      t.boolean :pilot_summary_enabled, default: false, null: false
      t.boolean :pilot_csat_analysis_enabled, default: false, null: false
      t.boolean :pilot_follow_up_enabled, default: false, null: false
      t.boolean :pilot_rewrite_enabled, default: false, null: false
      t.boolean :pilot_label_suggestion_enabled, default: false, null: false
    end

    add_index :accounts, :id, name: 'index_accounts_on_pilot_enabled', where: 'pilot_enabled'
  end
end
