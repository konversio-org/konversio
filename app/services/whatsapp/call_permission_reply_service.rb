class Whatsapp::CallPermissionReplyService
  REQUESTS_KEY = 'call_permission_requests'.freeze
  REQUESTED_AT_KEY = 'call_permission_requested_at'.freeze
  MESSAGE_ID_KEY = 'call_permission_request_message_id'.freeze

  pattr_initialize [:inbox!, :params!]

  def perform
    return unless inbox.channel.voice_enabled?

    reply = extract_reply
    return unless reply && reply[:accepted]

    conversation = find_requesting_conversation(reply[:context_id])
    return unless conversation

    clear_request(conversation, reply[:context_id])
    emit_activity(conversation)
    broadcast_granted(conversation)
  end

  private

  def extract_reply
    message = params.dig(:entry, 0, :changes, 0, :value, :messages, 0)
    reply = message&.dig(:interactive, :call_permission_reply)
    return if reply.blank?

    { accepted: reply[:response] == 'accept', context_id: message.dig(:context, :id) }
  end

  # Match the reply to the conversation whose request message it points at
  # (interactive replies carry context.id = our outbound wamid).
  def find_requesting_conversation(context_id)
    return if context_id.blank?

    inbox.conversations.where.not(status: :resolved).find do |conversation|
      request_message_ids(conversation).include?(context_id)
    end
  end

  def request_message_ids(conversation)
    attrs = conversation.additional_attributes || {}
    ids = attrs.fetch(REQUESTS_KEY, {}).values.filter_map { |request| request[MESSAGE_ID_KEY] }
    ids << attrs[MESSAGE_ID_KEY] if attrs[MESSAGE_ID_KEY].present?
    ids
  end

  def clear_request(conversation, context_id)
    conversation.reload.with_lock do
      attrs = conversation.additional_attributes || {}
      requests = attrs.fetch(REQUESTS_KEY, {}).reject { |_recipient, request| request[MESSAGE_ID_KEY] == context_id }
      attrs = attrs.except(REQUESTED_AT_KEY, MESSAGE_ID_KEY) if attrs[MESSAGE_ID_KEY] == context_id
      attrs = permission_attrs(attrs, requests)
      conversation.update!(additional_attributes: attrs)
    end
  end

  def permission_attrs(attrs, requests)
    return attrs.merge(REQUESTS_KEY => requests) if requests.present?

    attrs.except(REQUESTS_KEY)
  end

  def emit_activity(conversation)
    content = I18n.t('conversations.activity.whatsapp_call.permission_granted', contact_name: conversation.contact.name)
    ::Conversations::ActivityMessageJob.perform_later(
      conversation,
      { account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity, content: content }
    )
  end

  def broadcast_granted(conversation)
    contact = conversation.contact
    ActionCable.server.broadcast(
      "account_#{inbox.account_id}",
      {
        event: 'voice_call.permission_granted',
        data: { account_id: inbox.account_id, conversation_id: conversation.id,
                contact_name: contact.name, contact_phone: contact.phone_number }
      }
    )
  end
end
