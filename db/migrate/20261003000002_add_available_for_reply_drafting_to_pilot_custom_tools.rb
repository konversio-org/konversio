class AddAvailableForReplyDraftingToPilotCustomTools < ActiveRecord::Migration[7.2]
  def change
    add_column :pilot_custom_tools, :available_for_reply_drafting, :boolean, default: false, null: false
  end
end
