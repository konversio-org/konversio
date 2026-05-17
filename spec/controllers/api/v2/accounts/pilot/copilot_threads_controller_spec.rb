require 'rails_helper'

RSpec.describe 'Api::V2::Accounts::Pilot::CopilotThreads', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:url) { "/api/v2/accounts/#{account.id}/pilot/copilot_threads" }

  before do
    account.update!(pilot_enabled: true, pilot_copilot_enabled: true)
  end

  describe 'POST /api/v2/accounts/:account_id/pilot/copilot_threads' do
    it 'creates the thread, persists the user message, enqueues the inference job, and returns 201' do
      expect do
        post url,
             params: { message: 'Refund policy question', assistant_id: 7 },
             headers: agent.create_new_auth_token,
             as: :json
      end.to have_enqueued_job(Pilot::CopilotInferenceJob)
        .with(hash_including(thread_id: an_instance_of(Integer)))

      expect(response).to have_http_status(:created)
      thread_id = response.parsed_body['id']
      thread = Pilot::CopilotThread.find(thread_id)
      expect(thread.user_id).to eq(agent.id)
      expect(thread.title).to eq('Refund policy question')
      expect(thread.copilot_messages.user.count).to eq(1)
      expect(thread.copilot_messages.user.first.message['content']).to eq('Refund policy question')
    end

    it 'returns 400 when the message param is missing' do
      post url,
           params: {},
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it 'returns 403 when pilot_copilot is disabled' do
      account.update!(pilot_copilot_enabled: false)

      post url,
           params: { message: 'hi' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 403 when the master pilot flag is off' do
      account.update!(pilot_enabled: false)

      post url,
           params: { message: 'hi' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 401 when unauthenticated' do
      post url, params: { message: 'hi' }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v2/accounts/:account_id/pilot/copilot_threads' do
    let!(:my_thread) { create(:pilot_copilot_thread, account: account, user: agent) }
    let!(:other_thread) { create(:pilot_copilot_thread, account: account, user: other_agent) }

    it 'returns only the threads owned by the requesting agent' do
      get url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['data'].pluck('id')
      expect(ids).to contain_exactly(my_thread.id)
    end

    it 'returns all account threads for administrators' do
      get url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['data'].pluck('id')
      expect(ids).to contain_exactly(my_thread.id, other_thread.id)
    end
  end
end
