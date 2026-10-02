# Meta error 138006 means the contact has not opted in to calls yet; send the
# opt-in template so a dial failure becomes a request instead of a raw error.
class Whatsapp::CallPermissionRequestService
  THROTTLE = 5.minutes
  REQUESTS_KEY = 'call_permission_requests'.freeze
  REQUESTED_AT_KEY = 'call_permission_requested_at'.freeze
  MESSAGE_ID_KEY = 'call_permission_request_message_id'.freeze

  pattr_initialize [:conversation!, :recipient!]

  # Locked so two agents calling the same contact can't both send the template.
  def perform
    conversation.reload.with_lock do
      next 'permission_pending' if throttled?

      sent = send_safely
      next 'failed' if sent.blank?

      record_request(sent)
      emit_activity
      'permission_requested'
    end
  end

  private

  def throttled?
    last = request_attrs[REQUESTED_AT_KEY]
    last.present? && Time.zone.parse(last) > THROTTLE.ago
  end

  # Treat transport errors as a falsy return so the caller answers 422, not 500.
  def send_safely
    provider_service.send_call_permission_request(recipient, *body_args)
  rescue StandardError => e
    Rails.logger.warn "[WHATSAPP CALL] permission request failed: #{e.class} #{e.message}"
    nil
  end

  def body_args
    custom_body = conversation.inbox.channel.provider_config&.dig('call_permission_request_body').presence
    custom_body ? [custom_body] : []
  end

  def emit_activity
    content = I18n.t('conversations.activity.whatsapp_call.permission_requested', contact_name: conversation.contact.name)
    ::Conversations::ActivityMessageJob.perform_later(
      conversation,
      { account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity, content: content }
    )
  end

  def record_request(sent)
    requested_at = Time.current.iso8601
    wamid = sent.dig('messages', 0, 'id')
    attrs = (conversation.additional_attributes || {}).merge(
      REQUESTED_AT_KEY => requested_at,
      MESSAGE_ID_KEY => wamid,
      REQUESTS_KEY => requests.merge(recipient_key => { REQUESTED_AT_KEY => requested_at, MESSAGE_ID_KEY => wamid })
    )
    conversation.update!(additional_attributes: attrs)
  end

  def provider_service
    @provider_service ||= conversation.inbox.channel.provider_service
  end

  def request_attrs
    requests.fetch(recipient_key, {})
  end

  # Legacy requests always targeted the contact phone; preserve their throttle
  # and reply WAMID under that identity before another recipient replaces them.
  def requests
    attrs = conversation.additional_attributes || {}
    stored = attrs.fetch(REQUESTS_KEY, {})
    return stored if stored.present?

    legacy = attrs.slice(REQUESTED_AT_KEY, MESSAGE_ID_KEY).compact
    phone = conversation.contact.phone_number&.delete('+')
    return {} if legacy.blank? || phone.blank?

    { phone => legacy }
  end

  def recipient_key
    recipient.to_s
  end
end
