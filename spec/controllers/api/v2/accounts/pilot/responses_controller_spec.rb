require 'rails_helper'

RSpec.describe 'Api::V2::Accounts::Pilot::Responses', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:base_url) { "/api/v2/accounts/#{account.id}/pilot/assistants/#{assistant.id}/responses" }

  before do
    account.enable_features!(:pilot, :pilot_autopilot)
    allow(Pilot::UpdateEmbeddingJob).to receive(:perform_later)
  end

  describe 'GET #index' do
    context 'when unauthenticated' do
      it 'returns 401' do
        get base_url, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the autopilot feature is disabled' do
      it 'returns 403' do
        account.disable_features!(:pilot_autopilot)

        get base_url, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when an agent (non-admin) requests the index' do
      it 'returns 403' do
        get base_url, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when the assistant belongs to another account' do
      it 'returns 404' do
        other_assistant = create(:pilot_assistant)
        cross_url = "/api/v2/accounts/#{account.id}/pilot/assistants/#{other_assistant.id}/responses"

        get cross_url, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with valid admin request' do
      before { create_list(:pilot_assistant_response, 3, assistant: assistant) }

      it 'returns paginated envelope with meta' do
        get base_url, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['data'].size).to eq(3)
        expect(body['meta']).to include(
          'current_page' => 1,
          'per_page' => 25,
          'total_count' => 3,
          'total_pages' => 1
        )
      end

      it 'orders results by created_at DESC' do
        get base_url, headers: admin.create_new_auth_token, as: :json

        ids = response.parsed_body['data'].map { |row| row['id'] }
        expect(ids).to eq(assistant.responses.order(created_at: :desc).pluck(:id))
      end
    end

    context 'with a search filter' do
      before do
        create(:pilot_assistant_response, assistant: assistant, question: 'How do I refund?', answer: 'Within 30 days.')
        create(:pilot_assistant_response, assistant: assistant, question: 'Shipping?', answer: 'Tracking info.')
      end

      it 'filters via ILIKE on question and answer' do
        get base_url,
            params: { search: 'refund' },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['data'].size).to eq(1)
        expect(body['data'].first['question']).to eq('How do I refund?')
      end
    end
  end

  describe 'POST #create' do
    let(:valid_attrs) { { question: 'New Q?', answer: 'New A.' } }

    it 'returns 403 for agents' do
      post base_url, params: valid_attrs, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'creates a new response and returns 201' do
      expect do
        post base_url, params: valid_attrs, headers: admin.create_new_auth_token, as: :json
      end.to change(Pilot::AssistantResponse, :count).by(1)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['question']).to eq('New Q?')
      expect(body['answer']).to eq('New A.')
      expect(body['status']).to eq('approved')
      expect(body['edited']).to be(true)
    end

    it 'ignores assistant_id from the body and uses the URL value' do
      other_assistant = create(:pilot_assistant, account: account)
      post base_url,
           params: valid_attrs.merge(assistant_id: other_assistant.id),
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:created)
      expect(Pilot::AssistantResponse.last.assistant_id).to eq(assistant.id)
    end

    it 'returns 422 when required fields are missing' do
      post base_url,
           params: { question: '' },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH #update' do
    let(:resource) { create(:pilot_assistant_response, assistant: assistant, edited: false) }

    it 'returns 403 for agents' do
      patch "#{base_url}/#{resource.id}",
            params: { answer: 'updated' },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'updates and marks the row as edited' do
      patch "#{base_url}/#{resource.id}",
            params: { answer: 'A revised answer.' },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(resource.reload.answer).to eq('A revised answer.')
      expect(resource.edited).to be(true)
      expect(response.parsed_body['edited']).to be(true)
    end

    it 'keeps edited=true on subsequent edits' do
      already_edited = create(:pilot_assistant_response, assistant: assistant, edited: true)

      patch "#{base_url}/#{already_edited.id}",
            params: { answer: 'Another revision.' },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(already_edited.reload.edited).to be(true)
    end

    it 'returns 404 when the response belongs to a different assistant' do
      other_assistant = create(:pilot_assistant, account: account)
      other_response = create(:pilot_assistant_response, assistant: other_assistant)

      patch "#{base_url}/#{other_response.id}",
            params: { answer: 'cross-assistant attempt' },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE #destroy' do
    let!(:resource) { create(:pilot_assistant_response, assistant: assistant) }

    it 'returns 403 for agents' do
      delete "#{base_url}/#{resource.id}",
             headers: agent.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'deletes the row and returns 204' do
      expect do
        delete "#{base_url}/#{resource.id}",
               headers: admin.create_new_auth_token,
               as: :json
      end.to change(Pilot::AssistantResponse, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end
end
