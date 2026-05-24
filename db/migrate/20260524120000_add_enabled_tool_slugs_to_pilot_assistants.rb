# frozen_string_literal: true

class AddEnabledToolSlugsToPilotAssistants < ActiveRecord::Migration[7.1]
  def change
    add_column :pilot_assistants, :enabled_tool_slugs, :jsonb, null: false, default: []

    reversible do |dir|
      dir.up { backfill_existing_assistants }
    end
  end

  private

  def backfill_existing_assistants
    execute <<~SQL.squish
      UPDATE pilot_assistants
      SET enabled_tool_slugs = COALESCE((
        SELECT jsonb_agg(pilot_custom_tools.slug ORDER BY pilot_custom_tools.created_at DESC)
        FROM pilot_custom_tools
        WHERE pilot_custom_tools.account_id = pilot_assistants.account_id
          AND pilot_custom_tools.enabled = TRUE
      ), '[]'::jsonb)
    SQL
  end
end
