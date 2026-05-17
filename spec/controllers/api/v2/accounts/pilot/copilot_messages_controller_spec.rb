require 'rails_helper'

RSpec.describe 'Api::V2::Accounts::Pilot::CopilotMessages', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let!(:thread) { create(:pilot_copilot_thread, account: account, user: agent) }
  let(:url) { "/api/v2/accounts/#{account.id}/pilot/copilot_threads/#{thread.id}/copilot_messages" }

  before do
    account.update!(pilot_enabled: true, pilot_copilot_enabled: true)
  end

  describe 'POST .../copilot_messages' do
    it 'persists the user message, enqueues the inference job, and returns 201' do
      expect do
        post url,
             params: { message: "What's our refund window?", conversation_id: 42 },
             headers: agent.create_new_auth_token,
             as: :json
      end.to have_enqueued_job(Pilot::CopilotInferenceJob)
        .with(thread_id: thread.id, conversation_id: 42)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['message_type']).to eq('user')
      expect(body['message']['content']).to eq("What's our refund window?")
    end

    it 'returns 400 when message is missing' do
      post url,
           params: { conversation_id: 42 },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it 'returns 403 when pilot_copilot is disabled' do
      account.update!(pilot_copilot_enabled: false)

      post url, params: { message: 'hi' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 404 when the thread belongs to another agent (no existence leak)' do
      post url,
           params: { message: 'hi' },
           headers: other_agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET .../copilot_messages' do
    let!(:user_message) { create(:pilot_copilot_message, copilot_thread: thread, account: account, message_type: :user, message: { content: 'first' }) }
    let!(:assistant_message) do
      create(:pilot_copilot_message, copilot_thread: thread, account: account, message_type: :assistant, message: { content: 'second' })
    end

    it 'returns messages in chronological order' do
      get url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      data = response.parsed_body['data']
      expect(data.pluck('id')).to eq([user_message.id, assistant_message.id])
    end

    it 'returns 404 to a foreign agent' do
      get url, headers: other_agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
