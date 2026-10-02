require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Pilot::Preferences', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/pilot/preferences" }

  describe 'GET /api/v1/accounts/:account_id/pilot/preferences' do
    context 'when unauthenticated' do
      it 'returns 401' do
        get base_url, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'exposes the false-promise guard setting, defaulting to off' do
        get base_url, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['false_promise_guard_enabled']).to be(false)
      end

      it 'reflects an enabled false-promise guard' do
        account.update!(pilot_false_promise_guard_enabled: true)

        get base_url, headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['false_promise_guard_enabled']).to be(true)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/pilot/preferences' do
    context 'when unauthenticated' do
      it 'returns 401' do
        patch base_url, params: { pilot_false_promise_guard_enabled: true }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'enables the false-promise guard' do
        patch base_url,
              params: { pilot_false_promise_guard_enabled: true },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['false_promise_guard_enabled']).to be(true)
        expect(account.reload.pilot_false_promise_guard_enabled).to be(true)
      end

      it 'disables the false-promise guard when false is sent' do
        account.update!(pilot_false_promise_guard_enabled: true)

        patch base_url,
              params: { pilot_false_promise_guard_enabled: false },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['false_promise_guard_enabled']).to be(false)
        expect(account.reload.pilot_false_promise_guard_enabled).to be(false)
      end

      it 'leaves the setting untouched when the param is absent' do
        account.update!(pilot_false_promise_guard_enabled: true)

        patch base_url,
              params: { pilot_document_sync_interval: 'weekly' },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['false_promise_guard_enabled']).to be(true)
        expect(account.reload.pilot_false_promise_guard_enabled).to be(true)
      end
    end
  end
end
