class AddAiAssigneeTypeToConversations < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_column :conversations, :ai_assignee_type, :string
    add_index :conversations, [:assignee_agent_bot_id, :ai_assignee_type],
              name: 'idx_conversations_on_agent_bot_and_ai_assignee_type',
              algorithm: :concurrently
  end
end
