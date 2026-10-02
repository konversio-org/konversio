require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Pilot::FaqSuggestions', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/pilot/faq_suggestions" }

  before do
    account.enable_features!(:pilot, :pilot_autopilot)
    allow(Pilot::UpdateFaqSuggestionEmbeddingJob).to receive(:perform_later)
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

    context 'with an administrator' do
      before do
        create_list(:pilot_faq_suggestion, 3, assistant: assistant, status: :open)
        create_list(:pilot_faq_suggestion, 2, assistant: assistant, status: :dismissed)
      end

      it 'lists only the open suggestions for the assistant with meta' do
        get base_url,
            params: { assistant_id: assistant.id, status: 'open' },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['data'].size).to eq(3)
        expect(body['data'].map { |row| row['status'] }.uniq).to eq(['open'])
        expect(body['meta']).to include('current_page' => 1, 'per_page' => 25, 'total_count' => 3, 'total_pages' => 1)
      end

      it 'returns dismissed suggestions when filtered by dismissed status' do
        get base_url,
            params: { assistant_id: assistant.id, status: 'dismissed' },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response.parsed_body['data'].size).to eq(2)
      end

      it 'orders by descending source count' do
        Pilot::FaqSuggestion.delete_all
        low = create(:pilot_faq_suggestion, assistant: assistant, source_count: 1)
        high = create(:pilot_faq_suggestion, assistant: assistant, source_count: 9)

        get base_url, headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['data'].map { |row| row['id'] }).to eq([high.id, low.id])
      end
    end

    context 'with a search filter' do
      before do
        create(:pilot_faq_suggestion, assistant: assistant, question: 'How do I refund?', answer: 'Within 30 days.')
        create(:pilot_faq_suggestion, assistant: assistant, question: 'Shipping?', answer: 'Tracking info.')
      end

      it 'matches question or answer case-insensitively' do
        get base_url,
            params: { search: '30 DAYS' },
            headers: admin.create_new_auth_token,
            as: :json

        body = response.parsed_body
        expect(body['data'].size).to eq(1)
        expect(body['data'].first['question']).to eq('How do I refund?')
      end
    end

    context 'with more than a page of records' do
      before { create_list(:pilot_faq_suggestion, 26, assistant: assistant) }

      it 'returns the second page slice with correct meta' do
        get base_url,
            params: { page: 2 },
            headers: admin.create_new_auth_token,
            as: :json

        body = response.parsed_body
        expect(body['data'].size).to eq(1)
        expect(body['meta']).to include('current_page' => 2, 'total_count' => 26, 'total_pages' => 2)
      end
    end

    context 'with a non-admin agent' do
      let(:inbox) { create(:inbox, account: account) }
      let(:other_inbox) { create(:inbox, account: account) }
      let(:visible_conversation) { create(:conversation, account: account, inbox: inbox) }
      let(:hidden_conversation) { create(:conversation, account: account, inbox: other_inbox) }
      let(:visible_suggestion) { create(:pilot_faq_suggestion, assistant: assistant) }
      let(:hidden_suggestion) { create(:pilot_faq_suggestion, assistant: assistant) }

      before do
        create(:inbox_member, user: agent, inbox: inbox)
        create(:pilot_faq_observation, conversation: visible_conversation, status: :attached, faq_suggestion: visible_suggestion)
        create(:pilot_faq_observation, conversation: hidden_conversation, status: :attached, faq_suggestion: hidden_suggestion)
      end

      it 'sees only suggestions observed in accessible conversations' do
        get base_url, headers: agent.create_new_auth_token, as: :json

        ids = response.parsed_body['data'].map { |row| row['id'] }
        expect(ids).to include(visible_suggestion.id)
        expect(ids).not_to include(hidden_suggestion.id)
      end

      it 'returns not-found for the detail of an inaccessible suggestion' do
        get "#{base_url}/#{hidden_suggestion.id}", headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET #show' do
    let(:suggestion) { create(:pilot_faq_suggestion, assistant: assistant, source_count: 3) }

    it 'returns the suggestion fields and source conversations with display ids' do
      conversation = create(:conversation, account: account)
      create(:pilot_faq_observation, conversation: conversation, status: :attached, faq_suggestion: suggestion)

      get "#{base_url}/#{suggestion.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include('id' => suggestion.id, 'question' => suggestion.question, 'source_count' => 3, 'status' => 'open')
      expect(body['assistant']).to include('id' => assistant.id, 'name' => assistant.name)
      expect(body['observations'].size).to eq(1)
      observation = body['observations'].first
      expect(observation['conversation']).to include('id' => conversation.id, 'display_id' => conversation.display_id)
      expect(observation).to include('generated_question', 'generated_answer', 'language', 'status', 'created_at')
    end

    context 'with a non-admin agent' do
      let(:inbox) { create(:inbox, account: account) }
      let(:other_inbox) { create(:inbox, account: account) }
      let(:accessible_conversation) { create(:conversation, account: account, inbox: inbox) }
      let(:hidden_conversation) { create(:conversation, account: account, inbox: other_inbox) }

      before do
        create(:inbox_member, user: agent, inbox: inbox)
        create(:pilot_faq_observation, conversation: accessible_conversation, status: :attached, faq_suggestion: suggestion)
        create(:pilot_faq_observation, conversation: hidden_conversation, status: :attached, faq_suggestion: suggestion)
      end

      it 'shows only the accessible conversation in the source preview' do
        get "#{base_url}/#{suggestion.id}", headers: agent.create_new_auth_token, as: :json

        ids = response.parsed_body['observations'].map { |row| row['conversation']['id'] }
        expect(ids).to eq([accessible_conversation.id])
      end
    end
  end

  describe 'PATCH #update' do
    it 'edits an open suggestion and keeps it open' do
      suggestion = create(:pilot_faq_suggestion, assistant: assistant)

      patch "#{base_url}/#{suggestion.id}",
            params: { question: 'Updated question?', answer: 'Updated answer.' },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:ok)
      suggestion.reload
      expect(suggestion.question).to eq('Updated question?')
      expect(suggestion.answer).to eq('Updated answer.')
      expect(suggestion.status).to eq('open')
    end

    it 'rejects blank values' do
      suggestion = create(:pilot_faq_suggestion, assistant: assistant)

      patch "#{base_url}/#{suggestion.id}",
            params: { question: '' },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'behaves as not-found for a dismissed suggestion and leaves values unchanged' do
      suggestion = create(:pilot_faq_suggestion, assistant: assistant, status: :dismissed)

      patch "#{base_url}/#{suggestion.id}",
            params: { question: 'Too late' },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:not_found)
      expect(suggestion.reload.question).not_to eq('Too late')
    end
  end

  describe 'POST #approve' do
    let(:suggestion) { create(:pilot_faq_suggestion, assistant: assistant, question: 'Q?', answer: 'A.') }

    it 'creates an approved knowledge entry and marks the suggestion approved' do
      post "#{base_url}/#{suggestion.id}/approve", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['status']).to eq('approved')
      expect(body['question']).to eq('Q?')

      entry = Pilot::AssistantResponse.find(body['id'])
      expect(entry).to be_approved
      expect(entry.assistant).to eq(assistant)
      expect(suggestion.reload.status).to eq('approved')
    end

    it 'applies final edits to the created entry and the suggestion' do
      post "#{base_url}/#{suggestion.id}/approve",
           params: { answer: 'Corrected.' },
           headers: admin.create_new_auth_token,
           as: :json

      body = response.parsed_body
      expect(body['answer']).to eq('Corrected.')
      expect(suggestion.reload.answer).to eq('Corrected.')
      expect(suggestion.status).to eq('approved')
    end

    it 'fails as not-found on double approval and creates exactly one entry' do
      post "#{base_url}/#{suggestion.id}/approve", headers: admin.create_new_auth_token, as: :json
      post "#{base_url}/#{suggestion.id}/approve", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(Pilot::AssistantResponse.where(assistant: assistant).count).to eq(1)
    end
  end

  describe 'POST #dismiss' do
    it 'marks an open suggestion dismissed' do
      suggestion = create(:pilot_faq_suggestion, assistant: assistant)

      post "#{base_url}/#{suggestion.id}/dismiss", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(suggestion.reload.status).to eq('dismissed')
    end

    it 'drops the dismissed suggestion from the default open list' do
      suggestion = create(:pilot_faq_suggestion, assistant: assistant)
      post "#{base_url}/#{suggestion.id}/dismiss", headers: admin.create_new_auth_token, as: :json

      get base_url, params: { status: 'open' }, headers: admin.create_new_auth_token, as: :json

      ids = response.parsed_body['data'].map { |row| row['id'] }
      expect(ids).not_to include(suggestion.id)
    end

    it 'behaves as not-found for an already dismissed suggestion' do
      suggestion = create(:pilot_faq_suggestion, assistant: assistant, status: :dismissed)

      post "#{base_url}/#{suggestion.id}/dismiss", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
