require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Pilot::Assistants', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/pilot/assistants" }

  before do
    account.enable_features!(:pilot, :pilot_autopilot)
  end

  describe 'GET /api/v1/accounts/:account_id/pilot/assistants' do
    context 'when unauthenticated' do
      it 'returns 401' do
        get base_url, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the pilot_autopilot feature is disabled' do
      it 'returns 403' do
        account.disable_features!(:pilot_autopilot)

        get base_url, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when authenticated as admin' do
      it 'returns an empty array when none exist' do
        get base_url, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body).to eq([])
      end

      it 'returns all assistants for the current account only' do
        create_list(:pilot_assistant, 2, account: account)
        create(:pilot_assistant, account: create(:account))

        get base_url, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.length).to eq(2)
        expect(response.parsed_body.first.keys).to include('id', 'name', 'description', 'config', 'enabled_tool_slugs', 'enabled_inbox_count')
      end
    end

    context 'when authenticated as agent' do
      it 'allows read access' do
        create(:pilot_assistant, account: account)

        get base_url, headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET /api/v1/accounts/:account_id/pilot/assistants/:id' do
    let(:assistant) { create(:pilot_assistant, account: account) }

    it 'returns the assistant for an admin' do
      get "#{base_url}/#{assistant.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq(assistant.id)
      expect(response.parsed_body['name']).to eq(assistant.name)
    end

    it 'returns 404 for cross-account access' do
      other_assistant = create(:pilot_assistant, account: create(:account))

      get "#{base_url}/#{other_assistant.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/pilot/assistants' do
    let(:valid_params) do
      {
        name: 'Test Assistant',
        description: 'A test assistant',
        config: { product_name: 'Konversio', temperature: 0.5 },
        enabled_tool_slugs: [],
        response_guidelines: ['Be polite'],
        guardrails: ['Never share personal data']
      }
    end

    it 'creates an assistant when admin' do
      tool = create(:pilot_custom_tool, account: account, title: 'Lookup order')

      expect do
        post base_url, params: valid_params.merge(enabled_tool_slugs: [tool.slug]), headers: admin.create_new_auth_token, as: :json
      end.to change(Pilot::Assistant, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['name']).to eq('Test Assistant')
      expect(response.parsed_body['config']['product_name']).to eq('Konversio')
      expect(response.parsed_body['enabled_tool_slugs']).to eq([tool.slug])
    end

    it 'returns 422 when name is missing' do
      post base_url, params: valid_params.except(:name), headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 401 when an agent tries to create' do
      post base_url, params: valid_params, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/pilot/assistants/:id' do
    let(:assistant) { create(:pilot_assistant, account: account) }

    it 'updates the assistant when admin' do
      tool = create(:pilot_custom_tool, account: account, title: 'Lookup order')

      patch "#{base_url}/#{assistant.id}",
            params: { name: 'Updated', description: 'Updated description', enabled_tool_slugs: [tool.slug] },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(assistant.reload.name).to eq('Updated')
      expect(assistant.enabled_tool_slugs).to eq([tool.slug])
    end

    it 'returns 401 when an agent tries to update' do
      patch "#{base_url}/#{assistant.id}",
            params: { name: 'Hacked' },
            headers: agent.create_new_auth_token,
            as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/pilot/assistants/:id' do
    let!(:assistant) { create(:pilot_assistant, account: account) }

    it 'destroys the assistant when admin' do
      expect do
        delete "#{base_url}/#{assistant.id}", headers: admin.create_new_auth_token, as: :json
      end.to change(Pilot::Assistant, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it 'returns 401 when an agent tries to delete' do
      delete "#{base_url}/#{assistant.id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/pilot/assistants/:id/playground' do
    let(:assistant) { create(:pilot_assistant, account: account) }
    let(:playground_url) { "#{base_url}/#{assistant.id}/playground" }
    let(:fake_result) { Custom::Pilot::AutopilotService::Result.new(reply: 'Hello there!', invoked_tool_names: [], handover: nil) }
    let(:fake_service) { instance_double(Custom::Pilot::AutopilotService, perform: fake_result) }

    before do
      allow(Custom::Pilot::AutopilotService).to receive(:new).and_return(fake_service)
    end

    it 'returns the assistant reply without persisting messages' do
      expect do
        post playground_url,
             params: { message_content: 'Hi', message_history: [{ role: 'user', content: 'Hi' }] },
             headers: agent.create_new_auth_token,
             as: :json
      end.not_to change(Message, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['reply']).to eq('Hello there!')
    end

    it 'does not create conversations' do
      expect do
        post playground_url,
             params: { message_content: 'Hi', message_history: [{ role: 'user', content: 'Hi' }] },
             headers: admin.create_new_auth_token,
             as: :json
      end.not_to change(Conversation, :count)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/pilot/assistants/tools' do
    it 'returns an array' do
      get "#{base_url}/tools", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to be_an(Array)
    end
  end
end
