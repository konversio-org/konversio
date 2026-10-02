# frozen_string_literal: true

# Drives `pilot_conversation_outcomes` episode recording from the internal
# event bus. Kept separate from `PilotResolveListener` (which is resolve-scoped
# mining): outcome recording also needs message, reopen, CSAT, and handoff
# signals.
#
# Every handler is best-effort. It only selects the event and delegates to
# `Pilot::ConversationOutcomeRecorder`, which owns all writes and swallows
# tracking errors so this listener can never alter the triggering flow.
class PilotOutcomeListener < BaseListener
  # First qualifying human reply on the covering episode.
  def message_created(event)
    message, account = extract_message_and_account(event)
    return unless pilot_enabled?(account)
    return unless message.present? && message.outgoing?

    recorder(conversation: message.conversation).record_human_reply(message: message)
  end

  # Resolution timestamp on the covering episode.
  def conversation_resolved(event)
    conversation, account = extract_conversation_and_account(event)
    return unless pilot_enabled?(account)

    recorder(conversation: conversation).record_resolution(at: event.timestamp)
  end

  # A transition away from `resolved` closes the open episode and opens a
  # reopen-triggered successor.
  def conversation_updated(event)
    conversation, account = extract_conversation_and_account(event)
    return unless pilot_enabled?(account)
    return unless reopened?(event)

    recorder(conversation: conversation).record_reopen(at: event.timestamp)
  end

  # CSAT ratings arrive as an update to the `input_csat` survey message. This
  # listener is registered after `CsatSurveyListener`, so the
  # `CsatSurveyResponse` read here has already been persisted for the event.
  def message_updated(event)
    message, account = extract_message_and_account(event)
    return unless pilot_enabled?(account)
    return unless message.present? && message.input_csat?

    # Look the response up directly rather than through the cached association:
    # `CsatSurveyListener` (registered earlier) may have created it after this
    # message object's association was cached as empty.
    response = ::CsatSurveyResponse.find_by(message_id: message.id)
    return if response.blank?

    recorder(conversation: message.conversation).record_csat(response: response)
  end

  # Handoff lifecycle event emitted by `Pilot::ConversationEvents`.
  def pilot_conversation_handed_off(event)
    conversation = event.data[:conversation]
    return unless pilot_enabled?(conversation&.account)

    recorder(conversation: conversation, assistant: event.data[:assistant])
      .record_handoff(at: event.timestamp, reason_category: event.data[:reason_category])
  end

  private

  def recorder(conversation:, assistant: nil)
    ::Pilot::ConversationOutcomeRecorder.new(conversation: conversation, assistant: assistant)
  end

  def pilot_enabled?(account)
    account.present? && account.feature_enabled?('pilot')
  end

  def reopened?(event)
    previous, current = status_change(event)
    previous == 'resolved' && current.present? && current != 'resolved'
  end

  def status_change(event)
    changed = event.data[:changed_attributes]
    return [] if changed.blank?

    value = changed[:status] || changed['status']
    value.is_a?(Array) ? value : []
  end
end
