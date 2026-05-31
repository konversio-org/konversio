# Shared handoff side-effects for the Pilot Autopilot. Extracted from
# `Pilot::AutopilotInferenceJob#perform_handoff` so both the inference path
# (LLM-signalled handover / inference error) and System B's evaluated
# not-complete branch produce identical results.
#
# Uses Chatwoot core's `bot_handoff!` to transition into the human-support
# path (only if not already `open`), marks the Pilot metadata envelope, posts
# the customer-visible message (skipped when blank — System B passes the
# assistant's handoff message which has no fallback), records the timeline
# activity, and dispatches telemetry. The conversation is left `open` — no
# resume timer; native auto-resolve closes it if the customer abandons it.
class Custom::Pilot::HandoffService
  def self.call(conversation:, assistant:, reason:, message:)
    new(conversation: conversation, assistant: assistant, reason: reason, message: message).call
  end

  def initialize(conversation:, assistant:, reason:, message:)
    @conversation = conversation
    @assistant = assistant
    @reason = reason
    @message = message
  end

  def call
    @conversation.bot_handoff! unless @conversation.open?
    transitioned_at = Time.zone.now

    mark_handoff_requested!(transitioned_at.iso8601)
    post_message if @message.present?
    append_activity_message
    dispatch_handover_event(transitioned_at)
  end

  private

  # Tags the conversation with the handoff envelope. The autopilot listener
  # keys off this metadata (`state == handoff_requested`) to decide whether
  # the assistant may still respond while a human is being reached.
  def mark_handoff_requested!(requested_at_iso)
    @conversation.additional_attributes ||= {}
    @conversation.additional_attributes['pilot_handoff'] = {
      'state' => 'handoff_requested',
      'requested_at' => requested_at_iso
    }
    @conversation.save!
  end

  def post_message
    @conversation.messages.create!(
      message_type: :outgoing,
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      sender: @assistant,
      content: @message
    )
  end

  # Appends a `message_type = activity` row so agents see the model-supplied
  # reason on the conversation timeline.
  def append_activity_message
    body = I18n.t('pilot.activity.handed_off_by_inference', reason: @reason.to_s)
    @conversation.messages.create!(
      message_type: :activity,
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      content: body
    )
  rescue StandardError => e
    Rails.logger.warn("[pilot.handoff_service] activity message persist failed: #{e.class}: #{e.message}")
  end

  def dispatch_handover_event(transitioned_at)
    envelope = ::Custom::Pilot::ConversationPayloadBuilder.call(conversation: @conversation, assistant: @assistant)
    payload = {
      account_id: @conversation.account_id,
      assistant_id: @assistant.id,
      conversation_envelope: envelope,
      reason: @reason
    }
    ::Custom::Pilot::EventDispatcher.dispatch(
      'pilot.autopilot.handover.triggered',
      payload,
      time: transitioned_at,
      account: @conversation.account
    )
  rescue StandardError => e
    Rails.logger.error("[pilot.handoff_service] handover dispatch failed: #{e.class}: #{e.message}")
  end
end
