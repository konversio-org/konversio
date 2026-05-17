# == Schema Information
#
# Table name: copilot_messages
#
#  id                :bigint           not null, primary key
#  message           :jsonb            not null
#  message_type      :integer          default("user")
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  copilot_thread_id :bigint           not null
#
# Indexes
#
#  index_copilot_messages_on_account_id         (account_id)
#  index_copilot_messages_on_copilot_thread_id  (copilot_thread_id)
#

# Single message inside a Copilot thread. `message_type` is an integer enum
# (`user`=0, `assistant`=1, `assistant_thinking`=2). The `message` JSONB
# column carries the rendered payload — at minimum `{ "content": "..." }`.
#
# On create the model dispatches `COPILOT_MESSAGE_CREATED` through the
# Rails dispatcher so subscribed clients can render the new message
# without polling.
class Captain::CopilotMessage < ApplicationRecord
  include Events::Types

  self.table_name = 'copilot_messages'

  belongs_to :copilot_thread, class_name: 'Captain::CopilotThread'
  belongs_to :account

  enum :message_type, { user: 0, assistant: 1, assistant_thinking: 2 }

  validates :message, presence: true

  after_create_commit :dispatch_message_created_event

  private

  def dispatch_message_created_event
    Rails.configuration.dispatcher.dispatch(
      COPILOT_MESSAGE_CREATED,
      Time.zone.now,
      copilot_message: self
    )
  end
end
