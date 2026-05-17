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
# Validator policy (see design.md D23 + pilot-copilot spec):
# - `message` MUST be a Hash AND `content` MUST be present.
# - Unknown keys are NOT rejected. Mistral, Qwen, gpt-4o-mini all emit
#   additional JSON fields (`tool_calls`, `finish_reason`, `usage`, ...)
#   whenever both tools and a structured-output schema are set on the
#   same chat. Chatwoot's Captain CopilotMessage enforces a four-key
#   allow-list and crashes the response job; Pilot deliberately does not.
#
# On create the model dispatches `COPILOT_MESSAGE_CREATED` through the
# Rails dispatcher so subscribed clients can render the new message
# without polling.
class Pilot::CopilotMessage < ApplicationRecord
  include Events::Types

  self.table_name = 'copilot_messages'

  belongs_to :copilot_thread, class_name: 'Pilot::CopilotThread'
  belongs_to :account

  enum :message_type, { user: 0, assistant: 1, assistant_thinking: 2 }

  validates :message, presence: true
  validate :message_shape_tolerant

  after_create_commit :dispatch_message_created_event

  private

  def message_shape_tolerant
    return errors.add(:message, 'must be a Hash') unless message.is_a?(Hash)

    content = message['content'] || message[:content]
    errors.add(:message, 'must include a content key') if content.nil? || content.to_s.empty?
  end

  def dispatch_message_created_event
    Rails.configuration.dispatcher.dispatch(
      COPILOT_MESSAGE_CREATED,
      Time.zone.now,
      copilot_message: self
    )
  end
end
