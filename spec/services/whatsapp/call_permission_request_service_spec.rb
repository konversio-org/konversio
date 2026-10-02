require 'rails_helper'

RSpec.describe Whatsapp::CallPermissionRequestService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, sync_templates: false, validate_provider_config: false,
                              provider_config: { 'api_key' => 'k', 'phone_number_id' => '1', 'source' => 'embedded_signup' })
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, name: 'Ada', phone_number: '+15550001111') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:provider) { instance_double(Whatsapp::Providers::WhatsappCloudService) }
  let(:recipient) { '15550001111' }

  before do
    account.enable_features('channel_voice')
    allow_any_instance_of(Channel::Whatsapp).to receive(:provider_service).and_return(provider) # rubocop:disable RSpec/AnyInstance
    allow(provider).to receive(:send_call_permission_request).and_return({ 'messages' => [{ 'id' => 'wamid.REQUEST' }] })
  end

  def perform
    described_class.new(conversation: conversation, recipient: recipient).perform
  end

  it 'sends the request, records the wamid and emits an activity note' do
    status = nil
    expect { status = perform }.to have_enqueued_job(Conversations::ActivityMessageJob)

    expect(status).to eq('permission_requested')
    expect(conversation.reload.additional_attributes['call_permission_request_message_id']).to eq('wamid.REQUEST')
  end

  it 'passes a custom inbox body when configured' do
    channel.update!(provider_config: channel.provider_config.merge('call_permission_request_body' => 'Custom body'))

    perform

    expect(provider).to have_received(:send_call_permission_request).with(recipient, 'Custom body')
  end

  it 'throttles repeat requests within the window' do
    perform

    expect(perform).to eq('permission_pending')
    expect(provider).to have_received(:send_call_permission_request).once
  end

  it 'returns failed when the provider send fails' do
    allow(provider).to receive(:send_call_permission_request).and_return(nil)

    expect(perform).to eq('failed')
  end
end
