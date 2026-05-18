require 'rails_helper'

RSpec.describe 'Api::V2::Accounts::Pilot::Rewrites', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v2/accounts/#{account.id}/pilot/rewrites" }

  before do
    account.update!(pilot_enabled: true, pilot_rewrite_enabled: true)
  end

  describe 'POST /api/v2/accounts/:account_id/pilot/rewrites' do
    it 'returns the rewritten text on the happy path' do
      allow_any_instance_of(Custom::Pilot::RewriteService)
        .to receive(:perform).and_return('Hi! Unfortunately we cannot refund this time, but...')

      post url,
           params: { text: 'Refund denied.', tone: 'friendly' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['rewritten']).to include('Hi!')
    end

    it 'returns 403 when the rewrite flag is off' do
      account.update!(pilot_rewrite_enabled: false)

      post url,
           params: { text: 'foo', tone: 'friendly' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 422 with allowed_tones on invalid tone' do
      post url,
           params: { text: 'foo', tone: 'passive_aggressive' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['allowed_tones']).to include('friendly')
    end

    it 'returns 400 when text is missing' do
      post url,
           params: { tone: 'friendly' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end
end
