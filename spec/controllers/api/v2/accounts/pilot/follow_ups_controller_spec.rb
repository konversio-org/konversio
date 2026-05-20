require 'rails_helper'

RSpec.describe 'Api::V2::Accounts::Pilot::FollowUps', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:inbox_member) { create(:inbox_member, user: agent, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { "/api/v2/accounts/#{account.id}/pilot/follow_ups" }

  before do
    account.enable_features!(:pilot, :pilot_follow_up)
  end

  describe 'POST /api/v2/accounts/:account_id/pilot/follow_ups' do
    it 'returns suggestion strings on the happy path' do
      allow_any_instance_of(Custom::Pilot::FollowUpService)
        .to receive(:perform).and_return(['Could you share your order number?'])

      post url,
           params: { conversation_id: conversation.display_id },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['suggestions']).to eq(['Could you share your order number?'])
    end

    it 'returns 403 when the follow_up flag is off' do
      account.disable_features!(:pilot_follow_up)

      post url,
           params: { conversation_id: conversation.display_id },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
