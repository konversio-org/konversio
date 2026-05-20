# Hooks the Pilot Autopilot inference into Chatwoot's MessageCreatedEvent
# pipeline. Enqueues `Pilot::AutopilotInferenceJob` for every inbound
# customer message in an inbox that has a `Pilot::Assistant` attached AND
# the account has `pilot_autopilot_enabled = true`. The job itself
# re-validates eligibility before talking to the LLM, so this listener is
# best-effort and safe to over-trigger.
class PilotAutopilotListener < BaseListener
  def message_created(event)
    message, account = extract_message_and_account(event)
    return if message.blank? || account.blank?
    return unless message.message_type == 'incoming'
    return if message.private?
    return unless autopilot_active?(account, message.inbox)
    # Only respond while the conversation is bot-handled. After
    # `Conversation#bot_handoff!` transitions status to `open`, a human
    # agent has taken over — the bot must stop firing inference on every
    # subsequent customer message to avoid handoff loops.
    return unless message.conversation&.pending?

    ::Pilot::AutopilotInferenceJob.perform_later(message_id: message.id)
  end

  # Enqueues the Pilot Label Suggestion job for every new conversation
  # when the account has `pilot_label_suggestion_enabled = true`. The
  # job is non-destructive: it populates `conversation.suggested_label_ids`
  # so the UI can offer one-click apply chips above the label selector.
  def conversation_created(event)
    conversation = extract_conversation_and_account(event)[0]
    return if conversation.blank?
    return unless label_suggestion_active?(conversation.account)

    ::Pilot::LabelSuggestionJob.perform_later(conversation.id)
  end

  private

  def label_suggestion_active?(account)
    return false unless account.respond_to?(:pilot_enabled) && account.pilot_enabled
    return false unless account.respond_to?(:pilot_label_suggestion_enabled) && account.pilot_label_suggestion_enabled

    true
  end

  def autopilot_active?(account, inbox)
    return false unless account.respond_to?(:pilot_enabled) && account.pilot_enabled
    return false unless account.respond_to?(:pilot_autopilot_enabled) && account.pilot_autopilot_enabled
    return false if inbox.blank?

    ::Pilot::Inbox.exists?(inbox_id: inbox.id)
  end
end
