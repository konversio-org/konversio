require 'rails_helper'

RSpec.describe 'Api::V2::Accounts::Pilot::Summaries', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:inbox_member) { create(:inbox_member, user: agent, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { "/api/v2/accounts/#{account.id}/pilot/summaries" }

  before do
    account.enable_features!(:pilot, :pilot_summary)
  end

  describe 'POST /api/v2/accounts/:account_id/pilot/summaries' do
    it 'returns the generated summary on the happy path' do
      allow_any_instance_of(Custom::Pilot::SummaryService)
        .to receive(:perform).and_return('Customer asked about a refund.')

      post url,
           params: { conversation_id: conversation.display_id },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['summary']).to eq('Customer asked about a refund.')
    end

    it 'returns 403 when the summary flag is off' do
      account.disable_features!(:pilot_summary)

      post url,
           params: { conversation_id: conversation.display_id },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 400 when conversation_id is missing' do
      post url, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:bad_request)
    end
  end
end
