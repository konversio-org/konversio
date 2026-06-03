class AddReplyToEmailToChannelEmail < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_email, :reply_to_email, :string
  end
end
