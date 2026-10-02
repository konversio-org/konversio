class Whatsapp::OneoffCampaignService
  pattr_initialize [:campaign!]

  def perform
    validate_campaign!
    recipients = materialize_recipients
    process_recipients(recipients)
    campaign.completed!
  end

  private

  delegate :inbox, to: :campaign
  delegate :channel, to: :inbox

  def validate_campaign_type!
    raise "Invalid campaign #{campaign.id}" unless whatsapp_campaign? && campaign.one_off?
  end

  def whatsapp_campaign?
    campaign.inbox.inbox_type == 'Whatsapp'
  end

  def validate_campaign_status!
    raise 'Completed Campaign' if campaign.completed?
  end

  def validate_provider!
    raise 'WhatsApp Cloud provider required' unless whatsapp_cloud_channel?
  end

  def validate_feature_flag!
    raise 'WhatsApp campaigns feature not enabled' unless campaign.account.feature_enabled?(:whatsapp_campaign)
  end

  def validate_campaign!
    validate_campaign_type!
    validate_campaign_status!
    validate_provider!
    validate_feature_flag!
  end

  def extract_audience_labels
    audience_label_ids = campaign.audience.select { |audience| audience['type'] == 'Label' }.pluck('id')
    campaign.account.labels.where(id: audience_label_ids).pluck(:title)
  end

  def audience_contacts
    campaign.account.contacts.tagged_with(extract_audience_labels, any: true)
  end

  # Every audience contact gets a recipient row up front so skipped and failed
  # outcomes are attributable even when no message or conversation is produced.
  def materialize_recipients
    audience_contacts.find_each.map do |contact|
      campaign.pilot_campaign_recipients.find_or_create_by!(contact: contact) do |recipient|
        recipient.account = campaign.account
        recipient.inbox = inbox
      end
    end
  end

  def process_recipients(recipients)
    recipients.each { |recipient| process_recipient(recipient) }

    Rails.logger.info "Campaign #{campaign.id} processing completed"
  end

  def process_recipient(recipient)
    contact = recipient.contact

    destination, destination_error = campaign_destination(contact)
    if destination.blank?
      Rails.logger.warn "Skipping campaign recipient contact_id=#{contact.id}: #{destination_error}"
      return recipient.mark_skipped!(destination_error)
    end

    if campaign.template_params.blank?
      Rails.logger.error "Skipping contact #{contact.name} - no template_params found for WhatsApp campaign"
      return recipient.mark_skipped!('Template parameters are missing')
    end

    processed_template_params = process_liquid_template_params(contact)
    return recipient.mark_skipped!('Template parameters could not be resolved') if processed_template_params.nil?

    recipient.update!(message_content: rendered_message_content(contact))
    deliver_template(recipient, destination, processed_template_params)
  end

  def process_liquid_template_params(contact)
    processed = Whatsapp::LiquidTemplateProcessorService.new(campaign: campaign, contact: contact)
                                                        .process_template_params(campaign.template_params)
    Rails.logger.info "Skipping contact #{contact.name} - liquid variables resolved to blank values" if processed.nil?

    processed
  rescue StandardError => e
    Rails.logger.error "Failed to process liquid template params for contact #{contact.id}: #{e.message}"
    nil
  end

  def deliver_template(recipient, destination, template_params)
    guard_error = authentication_guard_error(destination, template_params)
    return recipient.mark_skipped!(guard_error) if guard_error

    name, namespace, lang_code, processed_parameters = template_components(template_params)
    return recipient.mark_skipped!('Template name could not be resolved') if name.blank?

    payload = template_payload(name, namespace, lang_code, processed_parameters)
    message_id = channel.send_template(destination, payload, nil)
    return recipient.mark_sent!(message_id) if message_id.present?

    recipient.mark_failed!(message: 'WhatsApp provider did not return a message id')
  rescue StandardError => e
    Rails.logger.error "Failed to send WhatsApp template message to #{destination}: #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(5).join('\n')}"
    recipient.mark_failed!(message: e.message)
  end

  def authentication_guard_error(destination, template_params)
    Whatsapp::AuthenticationTemplateGuard.new(channel: channel, recipient: destination, template_params: template_params).error
  end

  def template_components(template_params)
    Whatsapp::TemplateProcessorService.new(channel: channel, template_params: template_params).call
  end

  def template_payload(name, namespace, lang_code, parameters)
    { name: name, namespace: namespace, lang_code: lang_code, parameters: parameters }
  end

  def rendered_message_content(contact)
    Liquid::CampaignTemplateService.new(campaign: campaign, contact: contact).call(campaign.message)
  rescue StandardError => e
    Rails.logger.warn "Failed to render campaign message for contact #{contact.id}: #{e.message}"
    nil
  end

  def campaign_destination(contact)
    return [contact.phone_number, nil] if contact.phone_number.present?

    bsuid_contact_inboxes = bsuid_contact_inboxes_for(contact)
    return [nil, 'Phone number and BSUID are missing'] if bsuid_contact_inboxes.empty?
    return [bsuid_contact_inboxes.first.source_id, nil] if bsuid_contact_inboxes.one?

    [nil, 'Multiple WhatsApp identities found; refusing to choose a destination']
  end

  def bsuid_contact_inboxes_for(contact)
    contact.contact_inboxes.where(inbox_id: inbox.id).select { |contact_inbox| bsuid_source_id?(contact_inbox.source_id) }
  end

  def bsuid_source_id?(source_id)
    source_id.to_s.delete_prefix('whatsapp:').match?(RegexHelper::WHATSAPP_BSUID_REGEX)
  end

  def whatsapp_cloud_channel?
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'
  end
end
