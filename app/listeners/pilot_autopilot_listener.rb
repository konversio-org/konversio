# Hooks the Pilot Autopilot inference into Chatwoot's MessageCreatedEvent
# pipeline. Enqueues `Pilot::AutopilotInferenceJob` for every inbound
# customer message in an inbox that has a `Pilot::Assistant` attached AND
# the account has the `pilot_autopilot` feature flag enabled. The job
# itself re-validates eligibility before talking to the LLM, so this
# listener is best-effort and safe to over-trigger.
class PilotAutopilotListener < BaseListener
  def message_created(event)
    message, account = extract_message_and_account(event)
    return if message.blank? || account.blank?
    return unless message.message_type == 'incoming'
    return if message.private?
    return unless autopilot_active?(account, message.inbox)
    return unless bot_eligible?(message.conversation)

    ::Pilot::AutopilotInferenceJob.perform_later(message_id: message.id)
  end

  # Enqueues the Pilot Label Suggestion job for every new conversation
  # when the account has the `pilot_label_suggestion` feature flag
  # enabled. The job is non-destructive: it populates
  # `conversation.suggested_label_ids` so the UI can offer one-click
  # apply chips above the label selector.
  def conversation_created(event)
    conversation = extract_conversation_and_account(event)[0]
    return if conversation.blank?
    return unless label_suggestion_active?(conversation.account)

    ::Pilot::LabelSuggestionJob.perform_later(conversation.id)
  end

  private

  # The bot may respond when the conversation is either:
  #   - still bot-handled (`pending`), the classic Autopilot path, or
  #   - `open` in the co-active window opened by `Conversation#bot_handoff!`
  #     and still gated by Pilot metadata as `handoff_requested`, with no
  #     human takeover (no assignee, no human outgoing reply since the
  #     handoff timestamp), AND the assistant has the
  #     `keep_assistant_active_during_handoff` toggle enabled.
  #
  # Any other state — resolved, snoozed, agent-owned `open`, or the toggle
  # turned off — silences the assistant.
  def bot_eligible?(conversation)
    return false if conversation.blank?
    return true if conversation.pending?

    warm_bot_active?(conversation)
  end

  def warm_bot_active?(conversation)
    return false unless conversation.open? && conversation.assignee_id.blank?
    return false unless handoff_requested?(conversation)
    return false unless coactive_enabled?(conversation.inbox)

    requested_at = parse_requested_at(conversation.additional_attributes.dig('pilot_handoff', 'requested_at'))
    requested_at.present? && !conversation.human_replied_since?(requested_at)
  end

  def handoff_requested?(conversation)
    handoff = conversation.additional_attributes&.dig('pilot_handoff')
    handoff.is_a?(Hash) && handoff['state'] == 'handoff_requested'
  end

  def coactive_enabled?(inbox)
    assistant = assistant_for(inbox)
    assistant.present? && assistant.keep_assistant_active_during_handoff
  end

  def assistant_for(inbox)
    return nil if inbox.blank?

    ::Pilot::Inbox.find_by(inbox_id: inbox.id)&.assistant
  end

  def parse_requested_at(value)
    Time.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end

  def label_suggestion_active?(account)
    return false unless account.feature_enabled?('pilot')
    return false unless account.feature_enabled?('pilot_label_suggestion')

    true
  end

  def autopilot_active?(account, inbox)
    return false unless account.feature_enabled?('pilot')
    return false unless account.feature_enabled?('pilot_autopilot')
    return false if inbox.blank?

    ::Pilot::Inbox.exists?(inbox_id: inbox.id)
  end
end
