class RenameCaptainTablesToPilot < ActiveRecord::Migration[7.0]
  TABLE_RENAMES = {
    captain_assistants: :pilot_assistants,
    captain_assistant_responses: :pilot_assistant_responses,
    captain_documents: :pilot_documents,
    captain_custom_tools: :pilot_custom_tools,
    captain_scenarios: :pilot_scenarios,
    captain_inboxes: :pilot_inboxes
  }.freeze

  # Rails' Postgres adapter auto-renames indexes whose names contain the
  # table name during rename_table (via rename_table_indexes); it also
  # auto-renames indexes that contain a renamed column during rename_column.
  # We rely on that behavior — no explicit rename_index calls are needed.
  def up
    TABLE_RENAMES.each { |old_name, new_name| rename_table old_name, new_name }
    rename_column :pilot_inboxes, :captain_assistant_id, :pilot_assistant_id
  end

  def down
    rename_column :pilot_inboxes, :pilot_assistant_id, :captain_assistant_id
    TABLE_RENAMES.each { |old_name, new_name| rename_table new_name, old_name }
  end
end
