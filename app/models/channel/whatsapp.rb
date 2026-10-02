# == Schema Information
#
# Table name: channel_whatsapp
#
#  id                             :bigint           not null, primary key
#  message_templates              :jsonb
#  message_templates_last_updated :datetime
#  phone_number                   :string           not null
#  provider                       :string           default("default")
#  provider_config                :jsonb
#  phone_number_health            :jsonb            not null
#  phone_number_health_checked_at :datetime
#  phone_number_health_error      :string
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  account_id                     :integer          not null
#
# Indexes
#
#  index_channel_whatsapp_on_phone_number                    (phone_number) UNIQUE
#  index_channel_whatsapp_on_phone_number_health_checked_at  (phone_number_health_checked_at)
#

class Channel::Whatsapp < ApplicationRecord
  include Channelable
  include Reauthorizable

  self.table_name = 'channel_whatsapp'
  EDITABLE_ATTRS = [:phone_number, :provider, { provider_config: {} }].freeze

  # default at the moment is 360dialog lets change later.
  PROVIDERS = %w[default whatsapp_cloud].freeze
  before_validation :ensure_webhook_verify_token

  validates :provider, inclusion: { in: PROVIDERS }
  validates :phone_number, presence: true, uniqueness: true
  validate :validate_provider_config

  after_create :sync_templates
  before_destroy :teardown_webhooks
  after_commit :setup_webhooks, on: :create, if: :should_auto_setup_webhooks?

  def name
    'Whatsapp'
  end

  def provider_service
    if provider == 'whatsapp_cloud'
      Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: self)
    else
      Whatsapp::Providers::Whatsapp360DialogService.new(whatsapp_channel: self)
    end
  end

  def mark_message_templates_updated
    # rubocop:disable Rails/SkipsModelValidations
    update_column(:message_templates_last_updated, Time.zone.now)
    # rubocop:enable Rails/SkipsModelValidations
  end

  delegate :send_message, to: :provider_service
  delegate :send_template, to: :provider_service
  delegate :sync_templates, to: :provider_service
  delegate :media_url, to: :provider_service
  delegate :api_headers, to: :provider_service

  # Konversio is self-hosted: the channel's own API key is always the template access token.
  # The upstream Chatwoot Cloud business-management-token branch is out of scope.
  def template_access_token
    provider_config['api_key']
  end

  def send_contact_info_request(identifier, message)
    raise NotImplementedError, 'Contact information requests require a WhatsApp Cloud provider' unless provider == 'whatsapp_cloud'

    Whatsapp::Providers::WhatsappCloudContactInfoRequestService.perform(self, identifier, message)
  end

  def setup_webhooks(is_coexistence: nil)
    perform_webhook_setup(is_coexistence: is_coexistence)
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP] Webhook setup failed: #{e.message}"
    prompt_reauthorization!
  end

  private

  def ensure_webhook_verify_token
    provider_config['webhook_verify_token'] ||= SecureRandom.hex(16) if provider == 'whatsapp_cloud'
  end

  def validate_provider_config
    errors.add(:provider_config, 'Invalid Credentials') unless provider_service.validate_provider_config?
  end

  def perform_webhook_setup(is_coexistence: nil)
    webhook_setup_service(is_coexistence: is_coexistence).perform
  end

  def webhook_setup_service(is_coexistence: nil)
    Whatsapp::WebhookSetupService.new(self, provider_config['business_account_id'], provider_config['api_key'], is_coexistence: is_coexistence)
  end

  def teardown_webhooks
    Whatsapp::WebhookTeardownService.new(self).perform
  end

  def should_auto_setup_webhooks?
    # Embedded signup and Manual V2 run webhook setup explicitly so their API
    # responses can reflect the real result instead of swallowing callback errors.
    explicitly_configured_sources = %w[embedded_signup manual_setup_v2]
    provider == 'whatsapp_cloud' && explicitly_configured_sources.exclude?(provider_config['source'])
  end
end
