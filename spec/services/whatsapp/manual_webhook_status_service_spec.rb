require 'rails_helper'

RSpec.describe Whatsapp::ManualWebhookStatusService do
  let(:channel) do
    create(
      :channel_whatsapp,
      provider: 'whatsapp_cloud',
      phone_number: '+15550001111',
      sync_templates: false,
      validate_provider_config: false
    ).tap do |record|
      record.provider_config = {
        'api_key' => 'token',
        'phone_number_id' => 'phone-456',
        'business_account_id' => 'waba-123',
        'source' => 'manual_setup_v2'
      }
      record.save!
    end
  end
  let(:api_client) { instance_double(Whatsapp::FacebookApiClient) }
  let(:callback_url) { "#{ENV.fetch('FRONTEND_URL', nil)}/webhooks/whatsapp/+15550001111" }

  before do
    allow(Whatsapp::FacebookApiClient).to receive(:new).with('token').and_return(api_client)
    allow_any_instance_of(Whatsapp::WebhookSetupService).to receive(:perform)
    allow_any_instance_of(Whatsapp::WebhookSetupService).to receive(:registration_error).and_return(nil)
  end

  describe '#perform' do
    it 'reports a configured callback and verified subscription from the phone-level override' do
      allow(api_client).to receive(:fetch_phone_number).with('phone-456', fields: 'webhook_configuration')
                                                       .and_return({ 'webhook_configuration' => { 'override_callback_uri' => callback_url } })
      allow(api_client).to receive(:fetch_subscribed_apps).with('waba-123').and_return({ 'data' => [{ 'id' => 'app' }] })

      expect(described_class.new(channel).perform).to eq(
        callback_verified: true,
        callback_configured: true,
        callback_url: callback_url,
        subscription_verified: true
      )
    end

    it 'falls back to the WABA-level override' do
      allow(api_client).to receive(:fetch_phone_number).with('phone-456', fields: 'webhook_configuration')
                                                       .and_return({ 'webhook_configuration' => {} })
      allow(api_client).to receive(:fetch_subscribed_apps).with('waba-123')
                                                          .and_return({ 'data' => [{ 'override_callback_uri' => callback_url }] })

      result = described_class.new(channel).perform
      expect(result[:callback_configured]).to be true
      expect(result[:subscription_verified]).to be true
    end

    it 'reports an unconfigured callback and no subscription' do
      allow(api_client).to receive(:fetch_phone_number).with('phone-456', fields: 'webhook_configuration')
                                                       .and_return({ 'webhook_configuration' => {} })
      allow(api_client).to receive(:fetch_subscribed_apps).with('waba-123').and_return({ 'data' => [] })

      result = described_class.new(channel).perform
      expect(result[:callback_configured]).to be false
      expect(result[:subscription_verified]).to be false
    end
  end
end
