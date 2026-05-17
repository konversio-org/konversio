class RenameCaptainTablesToPilot < ActiveRecord::Migration[7.0]
  TABLE_RENAMES = {
    captain_assistants: :pilot_assistants,
    captain_assistant_responses: :pilot_assistant_responses,
    captain_documents: :pilot_documents,
    captain_custom_tools: :pilot_custom_tools,
    captain_scenarios: :pilot_scenarios,
    captain_inboxes: :pilot_inboxes
  }.freeze

  # Postgres does not auto-rename indexes when a table is renamed.
  # Keyed by the post-rename (pilot_*) table name. Index rename runs
  # in both directions while the tables are in their pilot_* form.
  INDEX_RENAMES = {
    pilot_assistant_responses: {
      'index_captain_assistant_responses_on_account_id' => 'index_pilot_assistant_responses_on_account_id',
      'index_captain_assistant_responses_on_assistant_id' => 'index_pilot_assistant_responses_on_assistant_id',
      'index_captain_assistant_responses_on_status' => 'index_pilot_assistant_responses_on_status'
    },
    pilot_assistants: {
      'index_captain_assistants_on_account_id' => 'index_pilot_assistants_on_account_id'
    },
    pilot_custom_tools: {
      'index_captain_custom_tools_on_account_id_and_slug' => 'index_pilot_custom_tools_on_account_id_and_slug',
      'index_captain_custom_tools_on_account_id' => 'index_pilot_custom_tools_on_account_id'
    },
    pilot_documents: {
      'index_captain_documents_on_account_id_and_sync_status' => 'index_pilot_documents_on_account_id_and_sync_status',
      'index_captain_documents_on_account_id' => 'index_pilot_documents_on_account_id',
      'index_captain_documents_on_assistant_id_and_external_link' => 'index_pilot_documents_on_assistant_id_and_external_link',
      'index_captain_documents_on_assistant_id' => 'index_pilot_documents_on_assistant_id',
      'index_captain_documents_on_status' => 'index_pilot_documents_on_status'
    },
    pilot_inboxes: {
      'index_captain_inboxes_on_captain_assistant_id_and_inbox_id' => 'index_pilot_inboxes_on_pilot_assistant_id_and_inbox_id',
      'index_captain_inboxes_on_captain_assistant_id' => 'index_pilot_inboxes_on_pilot_assistant_id',
      'index_captain_inboxes_on_inbox_id' => 'index_pilot_inboxes_on_inbox_id'
    },
    pilot_scenarios: {
      'index_captain_scenarios_on_account_id' => 'index_pilot_scenarios_on_account_id',
      'index_captain_scenarios_on_assistant_id_and_enabled' => 'index_pilot_scenarios_on_assistant_id_and_enabled',
      'index_captain_scenarios_on_assistant_id' => 'index_pilot_scenarios_on_assistant_id',
      'index_captain_scenarios_on_enabled' => 'index_pilot_scenarios_on_enabled'
    }
  }.freeze

  def up
    TABLE_RENAMES.each { |old_name, new_name| rename_table old_name, new_name }
    rename_column :pilot_inboxes, :captain_assistant_id, :pilot_assistant_id
    each_index_rename { |table, from, to| rename_index table, from, to }
  end

  def down
    each_index_rename { |table, from, to| rename_index table, to, from }
    rename_column :pilot_inboxes, :pilot_assistant_id, :captain_assistant_id
    TABLE_RENAMES.each { |old_name, new_name| rename_table new_name, old_name }
  end

  private

  def each_index_rename
    INDEX_RENAMES.each do |table, renames|
      renames.each { |from, to| yield(table, from, to) }
    end
  end
end
