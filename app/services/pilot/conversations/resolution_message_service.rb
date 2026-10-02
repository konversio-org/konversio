# Single decision point for the customer-facing message posted when the
# inactivity sweep auto-resolves a Pilot conversation.
#
# Posts nothing when the assistant's resolution-message toggle is off;
# otherwise posts the assistant's configured resolution copy, falling back to
# a localized default in the account's locale. The message is outgoing and
# authored by the assistant. Both the time-based and the evaluated resolution
# paths delegate here so the toggle and the custom/default fallback cannot
# diverge.
class Pilot::Conversations::ResolutionMessageService
  def self.call(conversation:, assistant:)
    new(conversation: conversation, assistant: assistant).call
  end

  def initialize(conversation:, assistant:)
    @conversation = conversation
    @assistant = assistant
  end

  def call
    return unless @assistant.send_inactivity_resolution_message

    @conversation.messages.create!(
      message_type: :outgoing,
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      sender: @assistant,
      content: message_content
    )
  end

  private

  def message_content
    @assistant.resolution_message.presence || localized_default
  end

  def localized_default
    locale = @conversation.account&.locale.presence || I18n.default_locale
    I18n.with_locale(locale) { I18n.t('conversations.pilot.resolution') }
  end
end
