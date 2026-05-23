require 'rails_helper'

RSpec.describe 'Api::V2::Accounts::Pilot::CustomTools', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base_url) { "/api/v2/accounts/#{account.id}/pilot/custom_tools" }
  let(:public_ip) { '93.184.216.34' }

  before do
    account.enable_features!(:pilot, :pilot_tools)
  end

  describe 'GET /api/v2/accounts/:account_id/pilot/custom_tools' do
    context 'when unauthenticated' do
      it 'returns 401' do
        get base_url, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the pilot_tools feature is disabled' do
      it 'returns 403' do
        account.disable_features!(:pilot_tools)
        get base_url, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when authenticated as admin' do
      it 'returns all custom tools for the current account only' do
        create_list(:pilot_custom_tool, 2, account: account)
        create(:pilot_custom_tool, account: create(:account))

        get base_url, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.length).to eq(2)
        expect(response.parsed_body.first.keys).to include('id', 'title', 'endpoint_url', 'slug')
      end
    end

    context 'when authenticated as agent' do
      it 'allows read access' do
        create(:pilot_custom_tool, account: account)
        get base_url, headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET /api/v2/accounts/:account_id/pilot/custom_tools/:id' do
    let(:tool) { create(:pilot_custom_tool, account: account) }

    it 'returns the tool for an admin' do
      get "#{base_url}/#{tool.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq(tool.id)
      expect(response.parsed_body['title']).to eq(tool.title)
    end

    it 'returns 404 for cross-account access' do
      other_tool = create(:pilot_custom_tool, account: create(:account))
      get "#{base_url}/#{other_tool.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v2/accounts/:account_id/pilot/custom_tools' do
    let(:valid_params) do
      {
        title: 'New Custom Tool',
        description: 'Does something cool',
        endpoint_url: 'https://api.example.com/custom',
        http_method: 'POST',
        auth_type: 'none',
        param_schema: [{ name: 'query', type: 'string', required: true }]
      }
    end

    it 'creates a custom tool when admin' do
      expect do
        post base_url, params: valid_params, headers: admin.create_new_auth_token, as: :json
      end.to change(Pilot::CustomTool, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['title']).to eq('New Custom Tool')
    end

    it 'returns 422 when invalid (missing url)' do
      post base_url, params: valid_params.except(:endpoint_url), headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 403 when an agent tries to create' do
      post base_url, params: valid_params, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PATCH /api/v2/accounts/:account_id/pilot/custom_tools/:id' do
    let(:tool) { create(:pilot_custom_tool, account: account) }

    it 'updates the tool when admin' do
      patch "#{base_url}/#{tool.id}",
            params: { title: 'Updated Title' },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(tool.reload.title).to eq('Updated Title')
    end

    it 'returns 403 when an agent tries to update' do
      patch "#{base_url}/#{tool.id}",
            params: { title: 'Hacked' },
            headers: agent.create_new_auth_token,
            as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'DELETE /api/v2/accounts/:account_id/pilot/custom_tools/:id' do
    let!(:tool) { create(:pilot_custom_tool, account: account) }

    it 'destroys the tool when admin' do
      expect do
        delete "#{base_url}/#{tool.id}", headers: admin.create_new_auth_token, as: :json
      end.to change(Pilot::CustomTool, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it 'returns 403 when an agent tries to delete' do
      delete "#{base_url}/#{tool.id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST /api/v2/accounts/:account_id/pilot/custom_tools/test' do
    let(:test_params) do
      {
        title: 'Test Tool',
        endpoint_url: 'https://api.example.com/test',
        http_method: 'GET',
        param_schema: [{ name: 'query', type: 'string', required: true }],
        test_arguments: { query: 'test-value' }
      }
    end

    before do
      allow(Resolv).to receive(:getaddresses).with('api.example.com').and_return([public_ip])
    end

    it 'executes the tool and returns success when it returns 200' do
      stub_request(:get, "https://#{public_ip}/test")
        .to_return(status: 200, body: 'success-response')

      post "#{base_url}/test", params: test_params, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['success']).to be(true)
      expect(response.parsed_body['result']).to eq('success-response')
    end

    it 'returns success false and structured error when remote API returns error' do
      stub_request(:get, "https://#{public_ip}/test")
        .to_return(status: 500, body: 'error')

      post "#{base_url}/test", params: test_params, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['success']).to be(false)
      expect(response.parsed_body['error']).to eq('tool.http_error')
    end

    it 'returns 403 when agent tries to test' do
      post "#{base_url}/test", params: test_params, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
