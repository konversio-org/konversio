require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Pilot::AgentSessions', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) do
    create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: assistant)
  end
  let(:base_url) { "/api/v1/accounts/#{account.id}/pilot/agent_sessions" }

  before do
    account.enable_features!(:pilot, :pilot_autopilot)
  end

  describe 'GET /api/v1/accounts/:account_id/pilot/agent_sessions/:message_id' do
    let(:document) do
      create(:pilot_document, assistant: assistant, account: account,
                              external_link: 'https://example.com/guide', name: 'Guide')
    end
    let(:non_http_document) do
      create(:pilot_document, assistant: assistant, account: account,
                              external_link: 'mailto:help@example.com', name: 'Mail us')
    end
    let!(:user_faq) do
      create(:pilot_assistant_response, assistant: assistant, account: account,
                                        question: 'How do refunds work?', status: :approved, documentable: nil)
    end
    let!(:pending_faq) do
      create(:pilot_assistant_response, assistant: assistant, account: account,
                                        question: 'Pending?', status: :pending, documentable: nil)
    end
    let!(:mined_faq) do
      create(:pilot_assistant_response, assistant: assistant, account: account,
                                        question: 'Mined?', status: :approved, documentable: document)
    end
    let!(:scenario) { create(:pilot_scenario, assistant: assistant, account: account, title: 'Billing flow') }
    let(:session) do
      create(:pilot_agent_session,
             assistant: assistant,
             account: account,
             subject: conversation,
             result: message,
             llm_model: 'llm-x').tap do |record|
        record.update!(
          cited_document_ids: [document.id, non_http_document.id],
          used_faq_ids: [user_faq.id, pending_faq.id, mined_faq.id],
          scenario_ids: [scenario.id],
          run_context: { 'entries' => [{ 'role' => 'user', 'content' => 'hi' }] }
        )
      end
    end

    # rubocop:disable RSpec/MultipleExpectations
    it 'returns the session detail payload' do
      session

      get "#{base_url}/#{message.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['id']).to eq(session.id)
      expect(body['message_id']).to eq(message.id)
      expect(body['model']).to eq('llm-x')
      expect(body['run_context']).to eq([{ 'role' => 'user', 'content' => 'hi' }])

      guide = body['cited_sources'].find { |source| source['id'] == document.id }
      expect(guide['title']).to eq('Guide')
      expect(guide['link']).to eq('https://example.com/guide')

      mail = body['cited_sources'].find { |source| source['id'] == non_http_document.id }
      expect(mail['link']).to be_nil

      expect(body['used_faqs']).to eq([{ 'id' => user_faq.id, 'title' => 'How do refunds work?' }])
      expect(body['scenarios']).to eq([{ 'id' => scenario.id, 'title' => 'Billing flow' }])
    end
    # rubocop:enable RSpec/MultipleExpectations

    it 'returns 404 when the message has no recorded session' do
      get "#{base_url}/#{message.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for a message belonging to another account' do
      foreign = create(:message, account: create(:account), message_type: :outgoing)

      get "#{base_url}/#{foreign.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects an agent without access to the conversation' do
      session

      get "#{base_url}/#{message.id}", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 401 when unauthenticated' do
      session

      get "#{base_url}/#{message.id}", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
