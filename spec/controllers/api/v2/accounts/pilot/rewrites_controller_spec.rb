require 'rails_helper'

RSpec.describe 'Api::V2::Accounts::Pilot::Rewrites', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v2/accounts/#{account.id}/pilot/rewrites" }

  before do
    account.enable_features!(:pilot, :pilot_rewrite)
  end

  describe 'POST /api/v2/accounts/:account_id/pilot/rewrites' do
    it 'returns the rewritten text on the happy path' do
      allow_any_instance_of(Custom::Pilot::RewriteService)
        .to receive(:perform).and_return('Hi! Unfortunately we cannot refund this time, but...')

      post url,
           params: { text: 'Refund denied.', operation: 'friendly' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['rewritten']).to include('Hi!')
    end

    it 'accepts improve as an operation' do
      allow_any_instance_of(Custom::Pilot::RewriteService)
        .to receive(:perform).and_return('Polished draft.')

      post url,
           params: { text: 'we cant do that', operation: 'improve' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['rewritten']).to eq('Polished draft.')
    end

    it 'accepts fix_spelling_grammar as an operation' do
      allow_any_instance_of(Custom::Pilot::RewriteService)
        .to receive(:perform).and_return('We received your request.')

      post url,
           params: { text: 'we recieved you\'re requst', operation: 'fix_spelling_grammar' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['rewritten']).to eq('We received your request.')
    end

    it 'returns 403 when the rewrite flag is off' do
      account.disable_features!(:pilot_rewrite)

      post url,
           params: { text: 'foo', operation: 'friendly' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 422 with allowed_operations on invalid operation' do
      post url,
           params: { text: 'foo', operation: 'passive_aggressive' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['allowed_operations']).to include('friendly', 'improve', 'fix_spelling_grammar')
    end

    it 'returns 400 when text is missing' do
      post url,
           params: { operation: 'friendly' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it 'returns 400 when operation is missing' do
      post url,
           params: { text: 'foo' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end
end
