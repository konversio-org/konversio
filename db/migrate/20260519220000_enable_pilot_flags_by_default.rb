class EnablePilotFlagsByDefault < ActiveRecord::Migration[7.1]
  PILOT_FLAGS = %i[
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
    PILOT_FLAGS.each do |flag|
      change_column_default :accounts, flag, from: false, to: true
    end

    updates = PILOT_FLAGS.index_with { |_flag| true }
    Account.unscoped.in_batches.update_all(updates)
  end

  def down
    PILOT_FLAGS.each do |flag|
      change_column_default :accounts, flag, from: true, to: false
    end

    updates = PILOT_FLAGS.index_with { |_flag| false }
    Account.unscoped.in_batches.update_all(updates)
  end
end
