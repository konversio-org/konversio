require 'rails_helper'

RSpec.describe 'Conference API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:other_agent) { create(:user, account: account) }
  let(:channel) do
    create(:channel_twilio_sms, :with_phone_number, account: account, phone_number: '+15551239999',
                                                    api_key_sid: 'SK123', api_key_secret: 'secret', twiml_app_sid: 'AP123')
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+15550001111') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:call) do
    create(:call, account: account, inbox: inbox, conversation: conversation, provider: :twilio, provider_call_id: 'CA123', status: 'ringing')
  end

  before do
    channel.update_column(:voice_enabled, true) # rubocop:disable Rails/SkipsModelValidations
    create(:inbox_member, user: agent, inbox: inbox)
    create(:inbox_member, user: other_agent, inbox: inbox)
  end

  describe 'GET conference token' do
    it 'returns a WebRTC token' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/conference/token",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['token']).to be_present
    end
  end

  describe 'POST conference' do
    it 'claims the call for the joining agent' do
      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/conference",
           params: { conversation_id: conversation.display_id, call_sid: call.provider_call_id },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(call.reload.accepted_by_agent_id).to eq(agent.id)
    end

    it 'returns a conflict naming the accepting agent' do
      call.update!(accepted_by_agent: other_agent)

      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/conference",
           params: { conversation_id: conversation.display_id, call_sid: call.provider_call_id },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to include(other_agent.available_name)
      expect(call.reload.accepted_by_agent_id).to eq(other_agent.id)
    end
  end

  describe 'DELETE conference' do
    it 'tears down the provider and finalizes the call' do
      call.update!(status: 'in_progress', accepted_by_agent: agent, started_at: 5.seconds.ago)
      allow_any_instance_of(Voice::Twilio::ConferenceService).to receive(:end_conference) # rubocop:disable RSpec/AnyInstance

      delete "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/conference",
             params: { conversation_id: conversation.display_id, call_sid: call.provider_call_id },
             headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(call.reload.status).to eq('completed')
      expect(call.end_reason).to eq('agent_hangup')
    end
  end
end
