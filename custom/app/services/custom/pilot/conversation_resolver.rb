# Shared "close this conversation" side-effects for the Pilot Autopilot.
# Used by both System B (the idle sweep — legacy and evaluated-complete
# branches) and Action C (the in-conversation `[resolved]` accelerator).
#
# Posts an optional customer-facing closing message (authored by the
# assistant), records an agent-only private note with the resolution reason,
# then transitions the conversation to `resolved`. The conversation may be in
# any non-resolved state; pending → resolved is the common bot path.
class Custom::Pilot::ConversationResolver
  def self.resolve!(conversation:, assistant:, reason:, post_message: nil)
    new(conversation: conversation, assistant: assistant, reason: reason, post_message: post_message).resolve!
  end

  def initialize(conversation:, assistant:, reason:, post_message: nil)
    @conversation = conversation
    @assistant = assistant
    @reason = reason
    @post_message = post_message
  end

  def resolve!
    post_closing_message if @post_message.present?
    add_private_note
    @conversation.resolved!
  end

  private

  def post_closing_message
    @conversation.messages.create!(
      message_type: :outgoing,
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      sender: @assistant,
      content: @post_message
    )
  end

  # Customer-invisible note so agents see why Pilot closed the thread.
  def add_private_note
    @conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      content: I18n.t('pilot.activity.resolved_by_inference', reason: @reason.to_s)
    )
  rescue StandardError => e
    Rails.logger.warn("[pilot.conversation_resolver] private note persist failed: #{e.class}: #{e.message}")
  end
end
