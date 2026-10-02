require 'rails_helper'

RSpec.describe 'Microsoft Authorization API', type: :request do
  let(:account) { create(:account) }

  describe 'POST /api/v1/accounts/{account.id}/microsoft/authorization' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/microsoft/authorization"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'returns unathorized for agent' do
        post "/api/v1/accounts/#{account.id}/microsoft/authorization",
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'creates a new authorization and returns the redirect url' do
        post "/api/v1/accounts/#{account.id}/microsoft/authorization",
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)

        # Validate URL components
        url = response.parsed_body['url']
        uri = URI.parse(url)
        params = CGI.parse(uri.query)

        expect(url).to start_with('https://login.microsoftonline.com/common/oauth2/v2.0/authorize')
        expected_scope = [
          'offline_access https://outlook.office.com/IMAP.AccessAsUser.All ' \
          'https://outlook.office.com/SMTP.Send openid profile email'
        ]
        expect(params['scope']).to eq(expected_scope)
        expect(params['redirect_uri']).to eq(["#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/microsoft/callback"])

        # Validate state parameter exists and can be decoded back to the account
        expect(params['state']).to be_present
        decoded_account = GlobalID::Locator.locate_signed(params['state'].first, for: 'default')
        expect(decoded_account).to eq(account)
      end

      it 'tags the state with the onboarding purpose when requested' do
        post "/api/v1/accounts/#{account.id}/microsoft/authorization",
             headers: administrator.create_new_auth_token,
             params: { return_to: 'onboarding' },
             as: :json

        state = CGI.parse(URI.parse(response.parsed_body['url']).query)['state'].first
        expect(GlobalID::Locator.locate_signed(state, for: 'onboarding')).to eq(account)
        expect(GlobalID::Locator.locate_signed(state, for: 'default')).to be_nil
      end
    end
  end
end
