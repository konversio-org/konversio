class Whatsapp::Providers::WhatsappCloudService < Whatsapp::Providers::BaseService
  def send_message(phone_number, message)
    @message = message

    if message.attachments.present?
      send_attachment_message(phone_number, message)
    elsif message.content_type == 'input_select'
      send_interactive_text_message(phone_number, message)
    else
      send_text_message(phone_number, message)
    end
  end

  def send_template(phone_number, template_info, message)
    template_body = template_body_parameters(template_info)

    request_body = {
      messaging_product: 'whatsapp',
      recipient_type: 'individual', # Only individual messages supported (not group messages)
      # BSUID -> `recipient`; phone number -> `to` (see recipient_params in the base provider).
      **recipient_params(phone_number),
      type: 'template',
      template: template_body
    }

    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: request_body.to_json
    )

    process_response(response, message)
  end

  def sync_templates
    # ensuring that channels with wrong provider config wouldn't keep trying to sync templates
    whatsapp_channel.mark_message_templates_updated
    return if (templates = fetch_whatsapp_templates).blank?

    # update_columns skips touch, so bump the cache key ourselves; only if templates changed
    whatsapp_channel.account.update_cache_key('inbox') if templates != whatsapp_channel.message_templates
    # rubocop:disable Rails/SkipsModelValidations
    whatsapp_channel.update_columns(message_templates: templates, message_templates_last_updated: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def fetch_whatsapp_templates(after: nil)
    options = { headers: { 'Authorization' => "Bearer #{whatsapp_channel.template_access_token}" } }
    options[:query] = { after: after } if after.present?
    response = HTTParty.get("#{business_account_path}/message_templates", options)
    unless response.success?
      Rails.logger.warn "[WHATSAPP] Template sync failed for account #{whatsapp_channel.account_id} " \
                        "inbox #{whatsapp_channel.inbox&.id}: #{response.code} #{error_message(response)}"
      return []
    end

    next_cursor = response.dig('paging', 'cursors', 'after')

    return response['data'] + fetch_whatsapp_templates(after: next_cursor) if next_cursor.present?

    response['data']
  end

  def validate_provider_config?
    response = HTTParty.get("#{business_account_path}/message_templates?access_token=#{whatsapp_channel.provider_config['api_key']}")
    response.success?
  end

  def api_headers
    { 'Authorization' => "Bearer #{whatsapp_channel.provider_config['api_key']}", 'Content-Type' => 'application/json' }
  end

  def create_csat_template(template_config)
    csat_template_service.create_template(template_config)
  end

  def delete_csat_template(template_name = nil)
    template_name ||= CsatTemplateNameService.csat_template_name(whatsapp_channel.inbox.id)
    csat_template_service.delete_template(template_name)
  end

  def get_template_status(template_name)
    csat_template_service.get_template_status(template_name)
  end

  def media_url(media_id)
    "#{api_base_path}/v13.0/#{media_id}"
  end

  # Marks the incoming customer message as read and shows WhatsApp's
  # "typing…" bubble. Meta clears the bubble when the next outbound
  # message is sent, or after 25s — whichever comes first.
  def mark_seen_with_typing(wamid)
    HTTParty.post(
      "#{api_base_path}/v22.0/#{whatsapp_channel.provider_config['phone_number_id']}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        status: 'read',
        message_id: wamid,
        typing_indicator: { type: 'text' }
      }.to_json
    )
  end

  private

  def csat_template_service
    @csat_template_service ||= Whatsapp::CsatTemplateService.new(whatsapp_channel)
  end

  def api_base_path
    ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
  end

  # TODO: See if we can unify the API versions and for both paths and make it consistent with out facebook app API versions
  def phone_id_path
    "#{api_base_path}/v13.0/#{whatsapp_channel.provider_config['phone_number_id']}"
  end

  def business_account_path
    "#{api_base_path}/v14.0/#{whatsapp_channel.provider_config['business_account_id']}"
  end

  def send_text_message(phone_number, message)
    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        context: whatsapp_reply_context(message),
        **recipient_params(phone_number),
        text: { body: message.outgoing_content },
        type: 'text'
      }.to_json
    )

    process_response(response, message)
  end

  def send_attachment_message(phone_number, message)
    attachment = message.attachments.first
    type = %w[image audio video].include?(attachment.file_type) ? attachment.file_type : 'document'
    type_content = {
      'link': attachment.download_url
    }
    type_content['caption'] = message.outgoing_content unless %w[audio sticker].include?(type)
    type_content['filename'] = attachment.file.filename if type == 'document'
    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: {
        :messaging_product => 'whatsapp',
        :context => whatsapp_reply_context(message),
        **recipient_params(phone_number),
        'type' => type,
        type.to_s => type_content
      }.to_json
    )

    process_response(response, message)
  end

  def error_message(response)
    # https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/#sample-response
    response.parsed_response&.dig('error', 'message')
  end

  def template_body_parameters(template_info)
    template_body = {
      name: template_info[:name],
      language: {
        policy: 'deterministic',
        code: template_info[:lang_code]
      }
    }

    # Enhanced template parameters structure
    # Note: Legacy format support (simple parameter arrays) has been removed
    # in favor of the enhanced component-based structure that supports
    # headers, buttons, and authentication templates.
    #
    # Expected payload format from frontend:
    # {
    #   processed_params: {
    #     body: { '1': 'John', '2': '123 Main St' },
    #     header: {
    #       media_url: 'https://...',
    #       media_type: 'image',
    #       media_name: 'filename.pdf' # Optional, for document templates only
    #     },
    #     buttons: [{ type: 'url', parameter: 'otp123456' }]
    #   }
    # }
    # This gets transformed into WhatsApp API component format:
    # [
    #   { type: 'body', parameters: [...] },
    #   { type: 'header', parameters: [...] },
    #   { type: 'button', sub_type: 'url', parameters: [...] }
    # ]
    template_body[:components] = template_info[:parameters] || []

    template_body
  end

  def whatsapp_reply_context(message)
    reply_to = message.content_attributes[:in_reply_to_external_id]
    return nil if reply_to.blank?

    {
      message_id: reply_to
    }
  end

  def send_interactive_text_message(phone_number, message)
    payload = create_payload_based_on_items(message)

    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        **recipient_params(phone_number),
        interactive: payload,
        type: 'interactive'
      }.to_json
    )

    process_response(response, message)
  end
end
