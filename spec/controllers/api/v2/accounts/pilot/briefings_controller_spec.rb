require 'rails_helper'

RSpec.describe 'Api::V2::Accounts::Pilot::Briefings', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:inbox_member) { create(:inbox_member, user: agent, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { "/api/v2/accounts/#{account.id}/pilot/briefings" }

  before do
    account.enable_features!(:pilot, :pilot_briefing)
  end

  describe 'POST /api/v2/accounts/:account_id/pilot/briefings' do
    context 'when the agent has conversation access and the feature is enabled' do
      it 'returns the generated draft' do
        allow_any_instance_of(Custom::Pilot::BriefingService)
          .to receive(:perform).and_return('Hi Alice, thanks for reaching out.')

        post url,
             params: { conversation_id: conversation.display_id },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['draft']).to eq('Hi Alice, thanks for reaching out.')
      end
    end

    context 'when the briefing feature flag is off' do
      it 'returns 403' do
        account.disable_features!(:pilot_briefing)

        post url,
             params: { conversation_id: conversation.display_id },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when the master pilot flag is off' do
      it 'returns 403' do
        account.disable_features!(:pilot)

        post url,
             params: { conversation_id: conversation.display_id },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when the agent has no access to the conversation' do
      let(:other_inbox) { create(:inbox, account: account) }
      let(:other_conversation) { create(:conversation, account: account, inbox: other_inbox) }

      it 'returns 403' do
        post url,
             params: { conversation_id: other_conversation.display_id },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when conversation_id is missing' do
      it 'returns 400' do
        post url,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when unauthenticated' do
      it 'returns 401' do
        post url, params: { conversation_id: conversation.display_id }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the underlying service raises an LLM error' do
      it 'returns 500' do
        allow_any_instance_of(Custom::Pilot::BriefingService)
          .to receive(:perform).and_raise(Custom::Pilot::BriefingService::Error, 'upstream timeout')

        post url,
             params: { conversation_id: conversation.display_id },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:internal_server_error)
        expect(response.parsed_body['error']).to eq('upstream timeout')
      end
    end
  end
end
