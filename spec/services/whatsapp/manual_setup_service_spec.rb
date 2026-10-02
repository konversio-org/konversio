require 'rails_helper'

RSpec.describe Whatsapp::ManualSetupService do
  let(:account) { create(:account) }
  let(:preview) do
    {
      verified_name: 'Acme Support',
      display_phone_number: '+15550001111',
      phone_number_id: 'phone-456',
      waba_id: 'waba-123',
      template_access: true,
      suggested_inbox_name: 'Acme Support WhatsApp'
    }
  end

  before do
    allow_any_instance_of(Whatsapp::ManualSetupValidationService).to receive(:perform).and_return(preview)
    allow_any_instance_of(Channel::Whatsapp).to receive(:sync_templates)
    allow_any_instance_of(Channel::Whatsapp).to receive(:validate_provider_config)
    webhook = instance_double(Whatsapp::WebhookSetupService, perform: nil, registration_error: nil)
    allow(Whatsapp::WebhookSetupService).to receive(:new).and_return(webhook)
  end

  describe '#perform' do
    it 'creates a whatsapp_cloud channel and inbox in a transaction' do
      setup = described_class.new(account: account, waba_id: 'waba-123', phone_number_id: 'phone-456', access_token: 'token').perform

      expect(setup.channel).to be_persisted
      expect(setup.channel.provider).to eq('whatsapp_cloud')
      expect(setup.channel.provider_config).to include(
        'api_key' => 'token',
        'phone_number_id' => 'phone-456',
        'business_account_id' => 'waba-123',
        'source' => 'manual_setup_v2'
      )
      expect(setup.channel.phone_number).to eq('+15550001111')
      expect(setup.channel.inbox.reload.name).to eq('Acme Support WhatsApp')
      expect(setup).to be_webhook_setup
    end

    it 'uses the submitted inbox name when present' do
      setup = described_class.new(account: account, waba_id: 'waba-123', phone_number_id: 'phone-456',
                                  access_token: 'token', inbox_name: 'Sales line').perform

      expect(setup.channel.inbox.reload.name).to eq('Sales line')
    end

    it 'still creates the inbox when webhook setup fails' do
      webhook = instance_double(Whatsapp::WebhookSetupService, perform: nil, registration_error: StandardError.new('Webhook setup failed'))
      allow(Whatsapp::WebhookSetupService).to receive(:new).and_return(webhook)

      setup = described_class.new(account: account, waba_id: 'waba-123', phone_number_id: 'phone-456', access_token: 'token').perform

      expect(setup.channel.inbox).to be_persisted
      expect(setup).not_to be_webhook_setup
      expect(setup.webhook_error).to eq('Webhook setup failed')
    end
  end
end
