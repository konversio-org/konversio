class Voice::CallMessageFactory
  attr_reader :call

  def initialize(call)
    @call = call
  end

  def perform!
    call.message || build_message!
  end

  def update_status!(status:, agent: nil, duration_seconds: nil)
    message = call.message
    return unless message

    patch = {
      'status' => status&.to_s&.tr('_', '-'),
      'accepted_by' => agent && { 'id' => agent.id, 'name' => agent.available_name },
      'duration_seconds' => duration_seconds
    }.compact
    message.update!(content_attributes: (message.content_attributes || {}).deep_merge('data' => patch))
    mirror_conversation_status!(status)
    message
  end

  private

  def build_message!
    message = Messages::MessageBuilder.new(author, call.conversation, message_params).perform
    mirror_conversation_status!(call.status)
    message
  end

  def message_params
    {
      content: I18n.t("conversations.messages.voice_call.#{call.provider}"),
      message_type: call.outgoing? ? 'outgoing' : 'incoming',
      content_type: 'voice_call',
      sender: call.outgoing? ? call.accepted_by_agent : call.contact,
      content_attributes: { 'data' => payload }
    }
  end

  def author
    call.outgoing? ? call.accepted_by_agent : call.contact
  end

  # `call_source` lets the dashboard tell Twilio and WhatsApp apart without a refetch.
  def payload
    {
      'call_id' => call.id,
      'call_sid' => call.provider_call_id,
      'call_source' => call.provider,
      'call_direction' => call.direction_label,
      'status' => call.display_status
    }
  end

  def mirror_conversation_status!(status)
    conversation = call.conversation
    conversation.update!(
      additional_attributes: (conversation.additional_attributes || {}).merge('call_status' => status.to_s.tr('_', '-'))
    )
  end
end
