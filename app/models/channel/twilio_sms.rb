# == Schema Information
#
# Table name: channel_twilio_sms
#
#  id                             :bigint           not null, primary key
#  account_sid                    :string           not null
#  api_key_secret                 :string
#  api_key_sid                    :string
#  auth_token                     :string           not null
#  content_templates              :jsonb
#  content_templates_last_updated :datetime
#  medium                         :integer          default("sms")
#  messaging_service_sid          :string
#  phone_number                   :string
#  provider_config                :jsonb
#  twiml_app_sid                  :string
#  voice_enabled                  :boolean          default(FALSE), not null
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  account_id                     :integer          not null
#
# Indexes
#
#  index_channel_twilio_sms_on_account_sid_and_phone_number  (account_sid,phone_number) UNIQUE
#  index_channel_twilio_sms_on_messaging_service_sid         (messaging_service_sid) UNIQUE
#  index_channel_twilio_sms_on_phone_number                  (phone_number) UNIQUE
#

class Channel::TwilioSms < ApplicationRecord
  include Channelable
  include CallSettings
  include Rails.application.routes.url_helpers

  self.table_name = 'channel_twilio_sms'

  # TODO: Remove guard once encryption keys become mandatory (target 3-4 releases out).
  encrypts :auth_token if Konversio.encryption_configured?
  encrypts :api_key_secret if Konversio.encryption_configured?

  validates :account_sid, presence: true
  # The same parameter is used to store api_key_secret if api_key authentication is opted
  validates :auth_token, presence: true

  EDITABLE_ATTRS = [
    :account_sid,
    :auth_token
  ].freeze

  # Must have _one_ of messaging_service_sid _or_ phone_number, and messaging_service_sid is preferred
  validates :messaging_service_sid, uniqueness: true, presence: true, unless: :phone_number?
  validates :phone_number, absence: true, if: :messaging_service_sid?
  validates :phone_number, uniqueness: true, allow_nil: true
  validate :voice_requires_phone_number, if: :voice_enabled?

  before_validation :provision_voice, on: :create, if: :voice_enabled?
  before_validation :reprovision_voice, on: :update, if: :voice_just_enabled?
  after_commit :teardown_voice, on: :update, if: :voice_just_disabled?

  enum medium: { sms: 0, whatsapp: 1 }

  def name
    medium == 'sms' ? 'Twilio SMS' : 'Whatsapp'
  end

  def send_message(to:, body:, media_url: nil)
    params = send_message_from.merge(to: to, body: body)
    params[:media_url] = media_url if media_url.present?
    params[:status_callback] = twilio_delivery_status_index_url
    client.messages.create(**params)
  end

  def initiate_call(to:)
    Voice::Twilio::Adapter.new(self).initiate_call(to: to)
  end

  # Re-points the TwiML app and the number at the voice webhooks, reusing the app.
  def reprovision_voice_webhooks!
    return unless voice_enabled?

    service = ::Twilio::VoiceProvisioningService.new(channel: self)
    update!(twiml_app_sid: service.sync!)
    service.configure_number!
  end

  def voice_call_webhook_url
    Rails.application.routes.url_helpers.twilio_voice_call_url(phone: phone_digits)
  end

  def voice_status_webhook_url
    Rails.application.routes.url_helpers.twilio_voice_status_url(phone: phone_digits)
  end

  # Voice channels store the secret in api_key_secret; SMS channels keep using
  # auth_token, and legacy API-key channels only set api_key_sid.
  def client
    if api_key_sid.present? && api_key_secret.present?
      Twilio::REST::Client.new(api_key_sid, api_key_secret, account_sid)
    elsif api_key_sid.present?
      Twilio::REST::Client.new(api_key_sid, auth_token, account_sid)
    else
      Twilio::REST::Client.new(account_sid, auth_token)
    end
  end

  private

  def phone_digits
    phone_number.to_s.delete_prefix('+')
  end

  def voice_requires_phone_number
    return if phone_number.present?

    errors.add(:base, 'Voice calling requires a phone number and cannot be used with a messaging service SID')
  end

  def voice_just_enabled?
    voice_enabled? && voice_enabled_changed?
  end

  def voice_just_disabled?
    !voice_enabled? && voice_enabled_previously_changed?
  end

  def provision_voice
    return if twiml_app_sid.present? || phone_number.blank?

    service = ::Twilio::VoiceProvisioningService.new(channel: self)
    service.verify_voice_capability!
    self.twiml_app_sid = service.provision!
  rescue StandardError => e
    Rails.logger.error("TWILIO_VOICE_SETUP failed: #{e.class} #{e.message} phone=#{phone_number}")
    errors.add(:base, "Twilio voice setup failed: #{e.message}")
  end

  alias reprovision_voice provision_voice

  def teardown_voice
    ::Twilio::VoiceProvisioningService.new(channel: self).teardown!
  end

  def send_message_from
    if messaging_service_sid?
      { messaging_service_sid: messaging_service_sid }
    else
      { from: phone_number }
    end
  end
end
