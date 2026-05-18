class AddSuggestedLabelIdsToConversations < ActiveRecord::Migration[7.1]
  def change
    add_column :conversations, :suggested_label_ids, :integer, array: true, default: [], null: false
  end
end
