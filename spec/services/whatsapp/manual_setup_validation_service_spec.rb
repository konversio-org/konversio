require 'rails_helper'

RSpec.describe Whatsapp::ManualSetupValidationService do
  let(:waba_id) { 'waba-123' }
  let(:phone_number_id) { 'phone-456' }
  let(:access_token) { 'token-789' }
  let(:api_client) { instance_double(Whatsapp::FacebookApiClient) }
  let(:service) do
    described_class.new(waba_id: waba_id, phone_number_id: phone_number_id, access_token: access_token)
  end

  let(:phone_data) do
    {
      'id' => phone_number_id,
      'display_phone_number' => '+1 555 000 1111',
      'verified_name' => 'Acme Support',
      'status' => 'CONNECTED',
      'code_verification_status' => 'VERIFIED'
    }
  end

  before do
    allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(api_client)
    allow(api_client).to receive(:fetch_all_phone_numbers).with(waba_id).and_return([phone_data])
    allow(api_client).to receive(:fetch_phone_number).with(phone_number_id, fields: 'status,code_verification_status')
                                                     .and_return({ 'status' => 'CONNECTED', 'code_verification_status' => 'VERIFIED' })
    allow(api_client).to receive(:fetch_message_templates).with(waba_id).and_return({ 'data' => [] })
    allow(api_client).to receive(:fetch_permissions).and_return({ 'data' => [{ 'permission' => 'whatsapp_business_messaging',
                                                                               'status' => 'granted' }] })
  end

  describe '#perform' do
    it 'returns a preview with normalized phone number and inbox name' do
      result = service.perform

      expect(result).to include(
        verified_name: 'Acme Support',
        display_phone_number: '+15550001111',
        phone_number_id: phone_number_id,
        waba_id: waba_id,
        template_access: true,
        suggested_inbox_name: 'Acme Support WhatsApp'
      )
    end

    it 'raises when a parameter is blank' do
      expect { described_class.new(waba_id: '', phone_number_id: '', access_token: '').perform }
        .to raise_error(ArgumentError, /WABA ID is required/)
    end

    it 'raises when the phone number does not belong to the WABA' do
      allow(api_client).to receive(:fetch_all_phone_numbers).with(waba_id).and_return([])

      expect { service.perform }.to raise_error(ArgumentError, /does not belong to the WABA ID/)
    end

    it 'raises when the phone is not ready at Meta' do
      allow(api_client).to receive(:fetch_all_phone_numbers).with(waba_id)
                                                            .and_return([phone_data.merge('status' => 'PENDING',
                                                                                          'code_verification_status' => 'NOT_VERIFIED')])
      allow(api_client).to receive(:fetch_phone_number).with(phone_number_id, fields: 'status,code_verification_status')
                                                       .and_return({ 'status' => 'PENDING', 'code_verification_status' => 'NOT_VERIFIED' })

      expect { service.perform }.to raise_error(ArgumentError, /Complete phone number verification in Meta/)
    end

    it 'raises when the display phone number is already connected' do
      create(:channel_whatsapp, phone_number: '+15550001111', provider: 'default', sync_templates: false, validate_provider_config: false)

      expect { service.perform }.to raise_error(ArgumentError, /already connected to another inbox/)
    end

    it 'raises when the phone number ID is already used' do
      channel = create(:channel_whatsapp, provider: 'whatsapp_cloud',
                                          phone_number: '+19998887777',
                                          sync_templates: false, validate_provider_config: false)
      channel.update_column(:provider_config, channel.provider_config.merge('phone_number_id' => phone_number_id))

      expect { service.perform }.to raise_error(ArgumentError, /already used by another WhatsApp inbox/)
    end

    it 'raises when the token cannot read message templates' do
      allow(api_client).to receive(:fetch_message_templates).with(waba_id).and_raise(StandardError, 'forbidden')

      expect { service.perform }.to raise_error(ArgumentError, /cannot access message templates/)
    end

    it 'raises when the token lacks the messaging permission' do
      allow(api_client).to receive(:fetch_permissions).and_return({ 'data' => [] })

      expect { service.perform }.to raise_error(ArgumentError, /cannot access WhatsApp messaging/)
    end
  end
end
