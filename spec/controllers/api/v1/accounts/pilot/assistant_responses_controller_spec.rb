require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Pilot::AssistantResponses', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/pilot/assistant_responses" }

  before do
    account.update!(pilot_enabled: true, pilot_autopilot_enabled: true)
    allow(Pilot::UpdateEmbeddingJob).to receive(:perform_later)
  end

  describe 'GET #index' do
    context 'when unauthenticated' do
      it 'returns 401' do
        get base_url, params: { assistant_id: assistant.id }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the autopilot feature is disabled' do
      it 'returns 403' do
        account.update!(pilot_autopilot_enabled: false)

        get base_url,
            params: { assistant_id: assistant.id },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when an agent (non-admin) requests the index' do
      it 'returns 403' do
        get base_url,
            params: { assistant_id: assistant.id },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when assistant_id is missing' do
      it 'returns 422' do
        get base_url, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when the assistant belongs to another account' do
      it 'returns 404' do
        other_assistant = create(:pilot_assistant)

        get base_url,
            params: { assistant_id: other_assistant.id },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with valid admin request' do
      before { create_list(:pilot_assistant_response, 3, assistant: assistant) }

      it 'returns paginated envelope with meta' do
        get base_url,
            params: { assistant_id: assistant.id },
            headers: admin.create_new_auth_token,
            as: :json

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
        get base_url,
            params: { assistant_id: assistant.id },
            headers: admin.create_new_auth_token,
            as: :json

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
            params: { assistant_id: assistant.id, search: 'refund' },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['data'].size).to eq(1)
        expect(body['data'].first['question']).to eq('How do I refund?')
      end
    end

    context 'with a status filter' do
      before do
        create(:pilot_assistant_response, assistant: assistant, status: :approved)
        create(:pilot_assistant_response, assistant: assistant, status: :pending)
      end

      it 'filters by status' do
        get base_url,
            params: { assistant_id: assistant.id, status: 'pending' },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['data'].size).to eq(1)
        expect(body['data'].first['status']).to eq('pending')
      end
    end

    context 'when a row has a documentable parent' do
      let(:document) { create(:pilot_document, assistant: assistant, account: account, name: 'Refund Policy') }

      before do
        create(:pilot_assistant_response, assistant: assistant, documentable: document)
        create(:pilot_assistant_response, assistant: assistant)
      end

      it 'embeds documentable when present and nulls it otherwise' do
        get base_url,
            params: { assistant_id: assistant.id },
            headers: admin.create_new_auth_token,
            as: :json

        rows = response.parsed_body['data']
        with_doc = rows.find { |row| row['documentable'].present? }
        without_doc = rows.find { |row| row['documentable'].nil? }

        expect(with_doc['documentable']).to include(
          'type' => 'Pilot::Document',
          'id' => document.id,
          'name' => 'Refund Policy'
        )
        expect(without_doc).not_to be_nil
      end
    end
  end

  describe 'GET #show' do
    let(:document) { create(:pilot_document, assistant: assistant, account: account, name: 'Pricing') }
    let(:resource) { create(:pilot_assistant_response, assistant: assistant, documentable: document) }

    it 'returns the row with embedded documentable' do
      get "#{base_url}/#{resource.id}",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['id']).to eq(resource.id)
      expect(body['documentable']).to include(
        'type' => 'Pilot::Document',
        'id' => document.id,
        'name' => 'Pricing'
      )
    end
  end

  describe 'POST #create' do
    let(:valid_attrs) do
      { assistant_id: assistant.id, question: 'New Q?', answer: 'New A.' }
    end

    it 'returns 403 for agents' do
      post base_url,
           params: valid_attrs,
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'creates a new response and returns 201' do
      expect do
        post base_url,
             params: valid_attrs,
             headers: admin.create_new_auth_token,
             as: :json
      end.to change(Pilot::AssistantResponse, :count).by(1)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['question']).to eq('New Q?')
      expect(body['answer']).to eq('New A.')
      expect(body['status']).to eq('approved')
      expect(body['edited']).to be(true)
    end

    it 'returns 422 when required fields are missing' do
      post base_url,
           params: { assistant_id: assistant.id, question: '' },
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
