require 'rails_helper'

RSpec.describe 'Api::V2::Accounts::Pilot::CopilotThreads', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:url) { "/api/v2/accounts/#{account.id}/pilot/copilot_threads" }

  before do
    account.enable_features!(:pilot, :pilot_copilot)
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
      account.disable_features!(:pilot_copilot)

      post url,
           params: { message: 'hi' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 403 when the master pilot flag is off' do
      account.disable_features!(:pilot)

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

  describe 'POST /api/v2/accounts/:account_id/pilot/copilot_threads (reply suggestion)' do
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }

    before do
      create(:inbox_member, user: agent, inbox: inbox)
      create(:message, account: account, conversation: conversation, inbox: inbox,
                       message_type: :incoming, content: 'Where is my order?')
    end

    it 'creates the thread, persists the first message, and enqueues the draft job' do
      expect do
        post url,
             params: { request_type: 'reply_suggestion', conversation_id: conversation.display_id, message: 'Draft a reply.' },
             headers: agent.create_new_auth_token,
             as: :json
      end.to have_enqueued_job(Pilot::CopilotReplySuggestionJob)
        .with(hash_including(thread_id: an_instance_of(Integer), conversation_id: conversation.display_id))

      expect(response).to have_http_status(:created)
      thread = Pilot::CopilotThread.find(response.parsed_body['id'])
      expect(thread.user_id).to eq(agent.id)
      expect(thread.copilot_messages.user.count).to eq(1)
    end

    it 'returns 404 for a conversation the agent cannot access and creates no thread' do
      other_inbox = create(:inbox, account: account)
      other_conversation = create(:conversation, account: account, inbox: other_inbox)

      expect do
        post url,
             params: { request_type: 'reply_suggestion', conversation_id: other_conversation.display_id, message: 'Draft.' },
             headers: agent.create_new_auth_token,
             as: :json
      end.not_to change(Pilot::CopilotThread, :count)

      expect(response).to have_http_status(:not_found)
    end

    it 'returns the same not-found shape for a missing conversation' do
      post url,
           params: { request_type: 'reply_suggestion', conversation_id: 999_999, message: 'Draft.' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq('error' => 'Conversation not found')
    end

    it 'returns 400 when no conversation reference is supplied' do
      post url,
           params: { request_type: 'reply_suggestion', message: 'Draft.' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it 'lets an administrator reference any conversation in the account' do
      other_inbox = create(:inbox, account: account)
      other_conversation = create(:conversation, account: account, inbox: other_inbox)
      create(:message, account: account, conversation: other_conversation, inbox: other_inbox,
                       message_type: :incoming, content: 'Help')

      post url,
           params: { request_type: 'reply_suggestion', conversation_id: other_conversation.display_id, message: 'Draft.' },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:created)
    end

    it 'keeps default chat behavior when no request type is supplied' do
      expect do
        post url,
             params: { message: 'Hello' },
             headers: agent.create_new_auth_token,
             as: :json
      end.to have_enqueued_job(Pilot::CopilotInferenceJob)
      expect(response).to have_http_status(:created)
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
