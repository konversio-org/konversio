require 'rails_helper'

RSpec.describe 'WhatsApp Calls API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, sync_templates: false, validate_provider_config: false,
                              provider_config: { 'api_key' => 'k', 'phone_number_id' => '1', 'business_account_id' => '2',
                                                 'source' => 'embedded_signup', 'calling_enabled' => true })
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+15550001111') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:provider) { instance_double(Whatsapp::Providers::WhatsappCloudService) }
  let(:headers) { agent.create_new_auth_token }

  before do
    account.enable_features('channel_voice')
    create(:inbox_member, user: agent, inbox: inbox)
    allow_any_instance_of(Channel::Whatsapp).to receive(:provider_service).and_return(provider) # rubocop:disable RSpec/AnyInstance
  end

  describe 'POST initiate' do
    before do
      allow(provider).to receive(:initiate_call).and_return({ 'calls' => [{ 'id' => 'wacid.1' }] })
    end

    it 'rejects a missing sdp offer' do
      post "/api/v1/accounts/#{account.id}/whatsapp_calls/initiate",
           params: { conversation_id: conversation.display_id }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'creates a ringing call and message' do
      post "/api/v1/accounts/#{account.id}/whatsapp_calls/initiate",
           params: { conversation_id: conversation.display_id, sdp_offer: 'offer-sdp' }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      call = Call.last
      expect(call).to be_whatsapp
      expect(call.status).to eq('ringing')
      expect(call.message).to be_present
      expect(call.provider_call_id).to eq('wacid.1')
    end

    it 'renders the permission-request state when the dial lacks permission' do
      allow(provider).to receive(:initiate_call).and_raise(Voice::CallErrors::NoCallPermission)
      allow(provider).to receive(:send_call_permission_request).and_return({ 'messages' => [{ 'id' => 'wamid.permission' }] })

      post "/api/v1/accounts/#{account.id}/whatsapp_calls/initiate",
           params: { conversation_id: conversation.display_id, sdp_offer: 'offer-sdp' }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['status']).to eq('permission_requested')
      expect(Call.count).to eq(0)
    end
  end

  describe 'POST upload_recording' do
    let(:call) { create(:call, account: account, inbox: inbox, conversation: conversation, contact: contact, provider: :whatsapp) }

    before do
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'outgoing')
      call.update!(message: message)
    end

    def upload
      post "/api/v1/accounts/#{account.id}/whatsapp_calls/#{call.id}/upload_recording",
           params: { recording: fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png') },
           headers: headers
    end

    it 'attaches the recording once' do
      upload
      expect(response).to have_http_status(:success)

      expect { upload }.not_to(change { call.message.reload.attachments.count })
      expect(call.message.attachments.count).to eq(1)
    end

    it 'refuses the upload when the recording snapshot is disabled' do
      call.update!(recording_enabled: false)

      expect { upload }.not_to(change { call.message.reload.attachments.count })
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
