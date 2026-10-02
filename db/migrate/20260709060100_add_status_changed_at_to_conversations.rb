class AddStatusChangedAtToConversations < ActiveRecord::Migration[7.1]
  def change
    add_column :conversations, :status_changed_at, :datetime
  end
end
